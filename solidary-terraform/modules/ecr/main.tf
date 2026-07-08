resource "aws_ecr_repository" "microservices" {
  for_each             = toset(var.service_names)
  name                 = "${var.project_name}-${each.value}"
  image_tag_mutability = "IMMUTABLE" 

  force_delete = true 

  image_scanning_configuration {
    scan_on_push = true 
  }

  tags = {
    Name = "${var.project_name}-${each.value}"
  }
}
