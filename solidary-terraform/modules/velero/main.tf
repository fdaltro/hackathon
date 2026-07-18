terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.0"
      configuration_aliases = [aws.dr]
    }
  }
}

# ==========================================================
# Estratégia de DR (Opção A - Multicloud/Cross-Region Backup):
# Velero fazendo backup do estado do cluster (manifestos +
# volumes) para um bucket S3 externo, independente do EKS.
#
# O bucket fica na região us-west-2 (aws.dr), diferente da região
# do cluster (us-east-1) - confirmado disponível nesta conta do
# AWS Academy. Isso garante que os manifestos do cluster sobrevivam
# mesmo a uma queda completa da região principal.
# ==========================================================

data "aws_caller_identity" "current" {}

# ==========================================================
# 1. BUCKET S3 DEDICADO PARA OS BACKUPS DO VELERO
# Criado na região de DR (aws.dr), não na região do cluster.
# ==========================================================
resource "aws_s3_bucket" "velero_backups" {
  provider      = aws.dr
  bucket        = "${var.project_name}-velero-backups-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # Permite destruir mesmo com objetos dentro (ambiente de lab)

  tags = {
    Name = "${var.project_name}-velero-backups"
  }
}

# Versionamento protege contra sobrescrita acidental de backups
resource "aws_s3_bucket_versioning" "velero_backups" {
  provider = aws.dr
  bucket   = aws_s3_bucket.velero_backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Bloqueia qualquer acesso público ao bucket de backup (boas práticas de segurança)
resource "aws_s3_bucket_public_access_block" "velero_backups" {
  provider                = aws.dr
  bucket                  = aws_s3_bucket.velero_backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ==========================================================
# 2. NAMESPACE DEDICADO
# ==========================================================
resource "kubernetes_namespace" "velero" {
  metadata {
    name = "velero"
  }
}

# ==========================================================
# 3. CREDENCIAIS AWS PARA O VELERO AUTENTICAR NO S3/EBS
# # ==========================================================
resource "kubernetes_secret" "velero_credentials" {
  metadata {
    name      = "cloud-credentials"
    namespace = kubernetes_namespace.velero.metadata[0].name
  }

  data = {
    cloud = <<-EOT
      [default]
      aws_access_key_id=${var.aws_access_key}
      aws_secret_access_key=${var.aws_secret_key}
      aws_session_token=${var.aws_session_token}
    EOT
  }

  type = "Opaque"
}

# ==========================================================
# 4. INSTALAÇÃO DO VELERO VIA HELM
# ==========================================================
resource "helm_release" "velero" {
  name       = "velero"
  repository = "https://vmware-tanzu.github.io/helm-charts"
  chart      = "velero"
  namespace  = kubernetes_namespace.velero.metadata[0].name
  timeout    = 600

  # Usa o secret que acabamos de criar em vez de deixar o Helm criar um novo
  set {
    name  = "credentials.existingSecret"
    value = kubernetes_secret.velero_credentials.metadata[0].name
  }

  # Plugin da AWS (obrigatório para o provider "aws" funcionar)
  set {
    name  = "initContainers[0].name"
    value = "velero-plugin-for-aws"
  }
  set {
    name  = "initContainers[0].image"
    value = "velero/velero-plugin-for-aws:v1.10.0"
  }
  set {
    name  = "initContainers[0].volumeMounts[0].mountPath"
    value = "/target"
  }
  set {
    name  = "initContainers[0].volumeMounts[0].name"
    value = "plugins"
  }

  # Local de armazenamento dos backups (manifestos do cluster) -
  # fica na região de DR, onde o bucket S3 realmente existe
  set {
    name  = "configuration.backupStorageLocation[0].name"
    value = "default"
  }
  set {
    name  = "configuration.backupStorageLocation[0].provider"
    value = "aws"
  }
  set {
    name  = "configuration.backupStorageLocation[0].bucket"
    value = aws_s3_bucket.velero_backups.bucket
  }
  set {
    name  = "configuration.backupStorageLocation[0].config.region"
    value = var.dr_region
  }

  # Local de snapshot dos volumes (EBS) - precisa ficar na MESMA região
  # do cluster/dos volumes (limitação física da AWS: não é possível
  # originar um snapshot de EBS diretamente em outra região)
  set {
    name  = "configuration.volumeSnapshotLocation[0].name"
    value = "default"
  }
  set {
    name  = "configuration.volumeSnapshotLocation[0].provider"
    value = "aws"
  }
  set {
    name  = "configuration.volumeSnapshotLocation[0].config.region"
    value = var.region
  }

  # Ativa o node-agent (backup de volumes via file-system, além dos
  # snapshots EBS) - cobre o "volumes" exigido pelo requisito de DR
  set {
    name  = "deployNodeAgent"
    value = "true"
  }
  set {
    name  = "configuration.uploaderType"
    value = "kopia"
  }

  depends_on = [
    kubernetes_secret.velero_credentials
  ]
}

# ==========================================================
# 5. AGENDAMENTO DE BACKUP (CRD "Schedule" do Velero)
# Frequência de 1h/1h, dado que o donation-service é o Hot Path
# (caminho crítico) da plataforma - RPO alvo de até 1 hora.
# ==========================================================
resource "kubectl_manifest" "solidary_backup_schedule" {
  yaml_body = <<-YAML
    apiVersion: velero.io/v1
    kind: Schedule
    metadata:
      name: solidary-hourly-backup
      namespace: velero
    spec:
      schedule: "0 * * * *"
      template:
        includedNamespaces:
          - solidary
          - observabilidade
          - argocd
        includeClusterResources: true
        # TTL reduzido para 7 dias (em vez de 30): com backup de hora em
        # hora, 30 dias gerariam ~720 backups acumulados no S3, o que
        # eleva custo de armazenamento sem necessidade real (FinOps).
        ttl: 168h0m0s
  YAML

  depends_on = [helm_release.velero]
}
