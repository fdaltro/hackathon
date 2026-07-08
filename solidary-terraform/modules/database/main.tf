locals {
  # Mapeamento atualizado para os serviços da Solidary Tech
  db_specs = [
    { name = "ngo_db",      id = "ngo" },
    { name = "donation_db", id = "donation" }
  ]
}

# DB Subnet Group para o RDS
resource "aws_db_subnet_group" "rds_sg" {
  name       = "${var.project_name}-rds-subnet-group"
  subnet_ids = var.private_subnets
  tags       = { Name = "${var.project_name}-rds-subnet-group" }
}

# Instâncias RDS (PostgreSQL) isoladas
resource "aws_db_instance" "postgresql" {
  count                  = 2
  
  identifier             = "${var.project_name}-db-${local.db_specs[count.index].id}"
  engine                 = "postgres"
  engine_version         = "15"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  
  db_name                = local.db_specs[count.index].name
  username               = "solidary_user"
  password               = "solidary_password"
  
  db_subnet_group_name   = aws_db_subnet_group.rds_sg.name
  skip_final_snapshot    = true
  publicly_accessible    = false
  vpc_security_group_ids = [var.db_sg_id]

  tags = { Name = "${var.project_name}-rds-${local.db_specs[count.index].id}" }
}