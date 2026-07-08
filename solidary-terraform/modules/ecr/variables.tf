variable "project_name" {}

variable "service_names" {
  type    = list(string)
  # Atualizado para as 3 imagens Docker que buildamos localmente
  default = ["ngo-service", "donation-service", "volunteer-service"]
}