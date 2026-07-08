variable "project_name" {}
variable "private_subnets" { type = list(string) }
variable "db_sg_id" { description = "Security Group ID para os bancos" }
variable "lab_role_arn" { description = "ARN da LabRole (AWS Academy)" }