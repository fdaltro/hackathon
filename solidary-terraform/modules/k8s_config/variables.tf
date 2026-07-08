variable "region" { type = string }
variable "rds_endpoints" { type = map(string) }
variable "sqs_queue_url" { type = string }
variable "dynamodb_table" { type = string }

# Estas variáveis serão preenchidas pelo env: TF_VAR_... do GitHub Actions
variable "aws_access_key" { type = string }
variable "aws_secret_key" { type = string }
variable "aws_session_token" { type = string }