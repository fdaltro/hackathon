variable "project_name" {
  type = string
}

variable "region" {
  type = string
}

# Região onde o bucket S3 de backup fica (diferente da região do cluster)
variable "dr_region" {
  type = string
}

# Reutiliza as mesmas credenciais temporárias do AWS Academy que já
# usamos no k8s_config, para o Velero conseguir autenticar no S3/EBS.
variable "aws_access_key" { type = string }
variable "aws_secret_key" { type = string }
variable "aws_session_token" { type = string }
