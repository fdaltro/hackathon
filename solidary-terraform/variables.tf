variable "region" {
  default = "us-east-1"
}

variable "project_name" {
  default = "solidary-tech"
}

variable "cluster_name" {
  default = "solidary-eks"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

# --- Variáveis de Autenticação GitHub Secrets ---
variable "aws_access_key" { type = string }
variable "aws_secret_key" { type = string }
variable "aws_session_token" { type = string }

# --- Observabilidade (nunca hardcode - injete via TF_VAR_* ou GitHub Secrets) ---
variable "datadog_api_key" {
  type      = string
  sensitive = true
}
variable "datadog_app_key" {
  type      = string
  sensitive = true
}
# Site da organização Datadog (ex: "datadoghq.com" para US1,
# "us5.datadoghq.com" para US5, "datadoghq.eu" para EU1, etc.)
# Confira em Organization Settings > "Site" no console da Datadog.
variable "datadog_site" {
  type    = string
  default = "datadoghq.com"
}
# COMENTADO: PagerDuty não está em uso no momento
# variable "pagerduty_integration_key" {
#   type      = string
#   sensitive = true
#   default   = ""
# }

# --- Tags Globais para FinOps ---
variable "default_tags" {
  type = map(string)
  default = {
    Project     = "SolidaryTech"
    Environment = "Production"
    CostCenter  = "FIAP-Fase5-Grupo12"
    ManagedBy   = "Terraform"
  }
}