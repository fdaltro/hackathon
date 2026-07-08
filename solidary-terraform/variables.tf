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