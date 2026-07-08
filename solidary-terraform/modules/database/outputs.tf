output "rds_endpoints" {
  description = "Endpoints dos bancos de dados mapeados por serviço"
  value = {
    ngo      = aws_db_instance.postgresql[0].endpoint
    donation = aws_db_instance.postgresql[1].endpoint
  }
}