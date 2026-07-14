variable "redis_endpoint" {
  type        = string
  description = "Endpoint do ElastiCache Redis (opcional: evita erro se não existir)"
  default     = ""
}

variable "datadog_api_key" {
  type        = string
  description = "Chave de API da Datadog (nunca hardcode - injete via TF_VAR_datadog_api_key)"
  sensitive   = true
}

# COMENTADO: PagerDuty não está em uso no momento.
# variable "pagerduty_integration_key" {
#   type        = string
#   description = "Integration Key do PagerDuty para o Alertmanager (via TF_VAR_pagerduty_integration_key)"
#   sensitive   = true
#   default     = ""
# }
