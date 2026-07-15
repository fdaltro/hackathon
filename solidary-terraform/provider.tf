terraform {
  required_version = ">= 1.0.0"

  # CORREÇÃO: O backend S3 PRECISA ficar aqui dentro do bloco terraform
  backend "s3" {
    bucket = "solidarytech-terraform-state-fase5"
    key    = "fase5/terraform.tfstate"
    region = "us-east-1"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
    datadog = {
      source  = "datadog/datadog"
      version = "~> 3.0"
    }
  }
}

# ==========================================================
# CONFIGURAÇÃO DOS PROVIDERS (Fora do bloco terraform {})
# ==========================================================
provider "aws" {
  region = var.region

  # Estratégia de FinOps: Tags herdadas por TODOS os recursos
  default_tags {
    tags = var.default_tags
  }
}

# Provider secundário para o bucket de backup do Velero, em uma região
# diferente da região do cluster (DR cross-region real - confirmado
# disponível nesta conta do AWS Academy).
provider "aws" {
  alias  = "dr"
  region = var.dr_region

  default_tags {
    tags = var.default_tags
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  load_config_file       = false
}

provider "datadog" {
  api_key = var.datadog_api_key
  app_key = var.datadog_app_key
  api_url = "https://api.${var.datadog_site}/"
}