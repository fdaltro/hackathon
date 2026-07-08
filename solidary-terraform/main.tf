# ==========================================================
# 1. REDE (JÁ PROVISIONADO)
# ==========================================================
module "network" {
  source       = "./modules/vpc"
  vpc_cidr     = var.vpc_cidr
  project_name = var.project_name
  cluster_name = var.cluster_name
}

# ==========================================================
# 2. BANCOS DE DADOS (JÁ PROVISIONADO)
# ==========================================================
module "database" {
  source          = "./modules/database"
  project_name    = var.project_name
  private_subnets = module.network.private_subnets
  db_sg_id        = module.network.db_security_group_id
  lab_role_arn    = data.aws_iam_role.labrole.arn
}

# ==========================================================
# 3. NOSQL VOLUNTÁRIOS (JÁ PROVISIONADO)
# ==========================================================
module "dynamodb" {
  source       = "./modules/dynamodb"
  project_name = var.project_name
}

# ==========================================================
# 4. MENSAGERIA SQS (JÁ PROVISIONADO)
# ==========================================================
module "sqs" {
  source       = "./modules/sqs"
  project_name = var.project_name
}

# ==========================================================
# 5. REPOSITÓRIOS DE IMAGENS (JÁ PROVISIONADO)
# ==========================================================
module "ecr" {
  source       = "./modules/ecr"
  project_name = var.project_name
}

# ==========================================================
# 🚀 DESCOMENTADO: NÚCLEO COMPUTACIONAL E CONFIGURAÇÕES
# ==========================================================
module "eks" {
  source       = "./modules/eks"
  cluster_name = var.cluster_name
  subnet_ids   = module.network.public_subnets # Subnets públicas para os nós (FinOps/Academy)
  lab_role_arn = data.aws_iam_role.labrole.arn
}

module "k8s_config" {
  source            = "./modules/k8s_config"
  region            = var.region
  rds_endpoints     = module.database.rds_endpoints
  sqs_queue_url     = module.sqs.sqs_url
  dynamodb_table    = module.dynamodb.table_name
  aws_access_key    = var.aws_access_key
  aws_secret_key    = var.aws_secret_key
  aws_session_token = var.aws_session_token
}

# ==========================================================
# ❌ CONTINUAM COMENTADOS: DEPLOY AUTOMÁTICO E TELEMETRIA
# ==========================================================
/*
module "argocd" {
  source     = "./modules/argocd"
  depends_on = [module.eks]
}

module "observability" {
  source     = "./modules/observability"
  depends_on = [module.eks]
}
*/