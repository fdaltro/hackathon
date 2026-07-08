output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnets" {
  value = aws_subnet.public[*].id
}

output "private_subnets" {
  value = aws_subnet.private[*].id
}

output "db_security_group_id" {
  description = "ID do Security Group criado para os bancos de dados"
  value       = aws_security_group.db_sg.id
}