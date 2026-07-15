# ==========================================================
# 1. CLUSTER EKS
# ==========================================================
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = var.lab_role_arn # Utilizando a LabRole obrigatória do Academy

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_public_access  = true
    endpoint_private_access = true
  }

  tags = {
    Name = var.cluster_name
  }
}

# ==========================================================
# 2. NODE GROUP (WORKER NODES OTIMIZADOS)
# ==========================================================
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-node-group"
  node_role_arn   = var.lab_role_arn
  subnet_ids      = var.subnet_ids

  # FinOps: Redução da escala para economizar créditos do Academy
  scaling_config {
    desired_size = 3 # Reduzido de 3
    max_size     = 3 # Reduzido de 4
    min_size     = 1
  }

  instance_types = ["t3.medium"] 

  tags = {
    Name = "${var.cluster_name}-node"
  }
}