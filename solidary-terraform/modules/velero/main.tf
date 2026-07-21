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

data "aws_caller_identity" "current" {}

# ==========================================================
# 1. NAMESPACE DEDICADO
# ==========================================================
resource "kubernetes_namespace" "velero" {
  metadata {
    name = "velero"
  }
}

# ==========================================================
# 2. CREDENCIAIS AWS PARA O VELERO AUTENTICAR NO S3/EBS
# ==========================================================
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
# 3. INSTALAÇÃO DO VELERO VIA HELM (Apontando para bucket fixo)
# ==========================================================
resource "helm_release" "velero" {
  name       = "velero"
  repository = "https://vmware-tanzu.github.io/helm-charts"
  chart      = "velero"
  namespace  = kubernetes_namespace.velero.metadata[0].name
  timeout    = 600

  set {
    name  = "credentials.existingSecret"
    value = kubernetes_secret.velero_credentials.metadata[0].name
  }

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

  # Aponta diretamente para o bucket criado manualmente na AWS (Oregon)
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
    value = "solidary-tech-velero-backups-158176292469"
  }
  set {
    name  = "configuration.backupStorageLocation[0].config.region"
    value = var.dr_region
  }

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
# 4. AGENDAMENTO DE BACKUP (CRD "Schedule" do Velero)
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
        ttl: 168h0m0s
  YAML

  depends_on = [helm_release.velero]
}