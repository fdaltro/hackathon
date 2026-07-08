resource "aws_sqs_queue" "donations_queue" {
  # Ajustado para adicionar o sufixo "-donations", formando "solidary-donations"
  name                      = "${var.project_name}-donations"
  delay_seconds             = 0
  max_message_size          = 262144
  message_retention_seconds = 86400 # 1 dia
  
  # FinOps: Long Polling para reduzir custos de API SQS
  receive_wait_time_seconds = 10

  tags = {
    Name = "${var.project_name}-donations-sqs"
  }
}