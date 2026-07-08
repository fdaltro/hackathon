# 1. Importação da LabRole existente para associar aos recursos (AWS Academy)
data "aws_iam_role" "labrole" {
  name = "LabRole"
}

# 2. Busca os dados do cluster EKS depois que ele for criado
data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
  
  # Garante que o Terraform só vai tentar ler isso se o módulo do EKS já estiver ativo
  depends_on = [module.eks] 
}

# 3. Gera o token de autenticação dinâmica para os providers (Kubernetes, Helm, Kubectl)
data "aws_eks_cluster_auth" "cluster" {
  name = var.cluster_name
  
  depends_on = [module.eks]
}