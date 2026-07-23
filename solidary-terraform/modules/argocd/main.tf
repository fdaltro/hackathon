terraform {
  required_providers {
    # Isso avisa ao módulo que o 'kubectl' vem do gavinbunney, não da hashicorp 
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
    }
    helm = {
      source  = "hashicorp/helm"
    }
  }
}

# 1. Criação do Namespace para o ArgoCD
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

# 2. Instalação do ArgoCD via Helm
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  version    = "7.7.1"

  set {
    name  = "server.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "server.extraArgs"
    value = "{--insecure}"
  }
}

# 3. CRIAÇÃO DINÂMICA DAS APLICAÇÕES
# Usamos kubectl_manifest para evitar erros de validação durante o 'plan'
resource "kubectl_manifest" "solidary_apps" {
  for_each = toset(["ngo-service", "donation-service", "volunteer-service"])

  yaml_body = <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: solidary-${each.key}
  namespace: argocd
spec:
  project: default
  source:
    repoURL: "https://github.com/fdaltro/hackathon.git"
    targetRevision: HEAD
    path: "solidary-gitops/apps/${each.key}"
  destination:
    server: "https://kubernetes.default.svc"
    namespace: solidary
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=false
YAML

  depends_on = [helm_release.argocd]
}

# ==========================================================
# Application dedicada para a pasta infrastructure/ (HPA e
# Ingress) - sem isso, esses manifestos nunca eram sincronizados
# pelo ArgoCD, mesmo existindo no repositório.
# ==========================================================
resource "kubectl_manifest" "solidary_infrastructure" {
  yaml_body = <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: solidary-infrastructure
  namespace: argocd
spec:
  project: default
  source:
    repoURL: "https://github.com/fdaltro/hackathon.git"
    targetRevision: HEAD
    path: "solidary-gitops/infrastructure"
  destination:
    server: "https://kubernetes.default.svc"
    namespace: solidary
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=false
YAML

  depends_on = [helm_release.argocd]
}
