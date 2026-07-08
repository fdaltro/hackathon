terraform {
  required_providers {
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

# 3. CRIAÇÃO DINÂMICA DAS APLICAÇÕES DA SOLIDARY TECH
resource "kubectl_manifest" "solidary_apps" {
  # Atualizado para os microsserviços do desafio atual
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
    # Lembre-se de criar esse repositório no seu GitHub para os manifestos K8s
    repoURL: "https://github.com/fdaltro/solidary-gitops.git"
    targetRevision: HEAD
    path: "apps/${each.key}"
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