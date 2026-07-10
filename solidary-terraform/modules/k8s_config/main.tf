# ==========================================================
# 1. CRIAÇÃO DO NAMESPACE
# ==========================================================
resource "kubernetes_namespace" "solidary" {
  metadata {
    name = "solidary"
  }
}

# ==========================================================
# 2. CREDENCIAIS AWS (ACADEMY)
# Necessário para os serviços que usam SQS e DynamoDB
# ==========================================================
resource "kubernetes_secret" "aws_credentials" {
  metadata {
    name      = "aws-credentials"
    namespace = kubernetes_namespace.solidary.metadata[0].name
  }

  data = {
    AWS_ACCESS_KEY_ID     = var.aws_access_key
    AWS_SECRET_ACCESS_KEY = var.aws_secret_key
    AWS_SESSION_TOKEN     = var.aws_session_token
    AWS_REGION            = var.region
  }

  type = "Opaque"
}

# ==========================================================
# 3. SERVIÇO: NGO-SERVICE
# ==========================================================
resource "kubernetes_config_map" "ngo_config" {
  metadata {
    name      = "ngo-config"
    namespace = kubernetes_namespace.solidary.metadata[0].name
  }

  data = {
    PORT = "8081"
  }
}

resource "kubernetes_secret" "ngo_secret" {
  metadata {
    name      = "ngo-secret"
    namespace = kubernetes_namespace.solidary.metadata[0].name
  }

  data = {
    DATABASE_URL = "postgres://solidary_user:solidary_password@${var.rds_endpoints["ngo"]}:5432/ngo_db"
  }

  type = "Opaque"
}

# ==========================================================
# 4. SERVIÇO: DONATION-SERVICE
# ==========================================================
resource "kubernetes_config_map" "donation_config" {
  metadata {
    name      = "donation-config"
    namespace = kubernetes_namespace.solidary.metadata[0].name
  }

  data = {
    PORT        = "8082"
    AWS_REGION  = var.region
    AWS_SQS_URL = var.sqs_queue_url
  }
}

resource "kubernetes_secret" "donation_secret" {
  metadata {
    name      = "donation-secret"
    namespace = kubernetes_namespace.solidary.metadata[0].name
  }

  data = {
    DATABASE_URL = "postgres://solidary_user:solidary_password@${var.rds_endpoints["donation"]}:5432/donation_db"
  }

  type = "Opaque"
}

# ==========================================================
# 5. SERVIÇO: VOLUNTEER-SERVICE
# ===========================================================
resource "kubernetes_config_map" "volunteer_config" {
  metadata {
    name      = "volunteer-config"
    namespace = kubernetes_namespace.solidary.metadata[0].name
  }

  data = {
    PORT               = "8083"
    AWS_REGION         = var.region
    AWS_DYNAMODB_TABLE = var.dynamodb_table
  }
}

# ===========================================================
# 6. PERMISSÃO AUTOMÁTICA PARA SELF-HEALING (AWS ACADEMY)
# Garante que a Lambda (via LabRole) possa executar o restart
# ==========================================================
resource "kubernetes_config_map_v1_data" "aws_auth_lambda" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  force = true

  data = {
    mapRoles = <<-EOF
- groups:
    - system:bootstrappers
    - system:nodes
  rolearn: arn:aws:iam::504491092699:role/LabNodesRole
  username: system:node:{{EC2PrivateDNSName}}
- groups:
    - system:masters
  rolearn: arn:aws:iam::504491092699:role/LabRole
  username: lambda-self-healing
EOF
  }
}