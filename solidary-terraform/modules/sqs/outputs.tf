output "sqs_url" {
  # O ID da fila no Terraform já retorna a URL completa necessária para o microsserviço
  value = aws_sqs_queue.donations_queue.id
}

output "sqs_arn" {
  value = aws_sqs_queue.donations_queue.arn
}