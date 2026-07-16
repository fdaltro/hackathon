# ===========================================================
# 1. REDE 
# ==========================================================
module "network" {
  source       = "./modules/vpc"
  vpc_cidr     = var.vpc_cidr
  project_name = var.project_name
  cluster_name = var.cluster_name
}

# ==========================================================
# 2. BANCOS DE DADOS 
# ==========================================================
module "database" {
  source          = "./modules/database"
  project_name    = var.project_name
  private_subnets = module.network.private_subnets
  db_sg_id        = module.network.db_security_group_id
  lab_role_arn    = data.aws_iam_role.labrole.arn
}

# ==========================================================
# 3. NOSQL VOLUNTÁRIOS 
# ==========================================================
module "dynamodb" {
  source       = "./modules/dynamodb"
  project_name = var.project_name
}

# ==========================================================
# 4. MENSAGERIA SQS 
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
# 🚀 DEPLOY AUTOMÁTICO VIA GITOPS
# ==========================================================
module "argocd" {
  source     = "./modules/argocd"
  depends_on = [module.eks]
}

# ==========================================================
# 🚀 TELEMETRIA
# ==========================================================
module "observability" {
  source                    = "./modules/observability"
  datadog_api_key           = var.datadog_api_key
  datadog_site              = var.datadog_site
  pagerduty_integration_key = var.pagerduty_integration_key
  depends_on                = [module.eks]
}

# ==========================================================
# 🛡️ DISASTER RECOVERY (Velero -> Backup para S3 externo)
# ==========================================================
module "velero" {
  source            = "./modules/velero"
  project_name      = var.project_name
  region            = var.region
  dr_region         = var.dr_region
  aws_access_key    = var.aws_access_key
  aws_secret_key    = var.aws_secret_key
  aws_session_token = var.aws_session_token
  depends_on        = [module.eks]

  providers = {
    aws    = aws
    aws.dr = aws.dr
  }
}