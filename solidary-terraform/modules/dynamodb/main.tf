resource "aws_dynamodb_table" "volunteers" {
  # Nome exato esperado pela aplicação
  name           = "SolidaryTechVolunteers"
  
  # FinOps: Modo sob demanda para economizar custos no Lab
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "volunteer_id"

  attribute {
    name = "volunteer_id"
    type = "S"
  }

  tags = { Name = "SolidaryTechVolunteers" }
}