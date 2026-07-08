# ==========================================================
# OUTPUTS DE VALIDAÇÃO DO KUBERNETES
# ==========================================================

output "config_status" {
  description = "Status do deploy das configurações no cluster"
  value       = "ConfigMaps e Secrets para os microserviços foram injetados com sucesso no namespace solidary."
}

output "configured_services" {
  description = "Lista de serviços que receberam configurações de banco de dados"
  value       = keys(var.rds_endpoints)
}

output "namespace_used" {
  description = "Namespace onde os recursos foram criados"
  value       = "solidary"
}