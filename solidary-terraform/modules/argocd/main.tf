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

# ==========================================================
# 1. Criação do Namespace para o ArgoCD
# ==========================================================
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

# ==========================================================
# 2. Instalação do ArgoCD via Helm
# ==========================================================
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  version    = "7.7.1"

  set {
    name  = "server.service.type"
    value = "ClusterIP"
  }

  set {
    name  = "server.extraArgs[0]"
    value = "--insecure"
  }
}

# ==========================================================
# 3. CRIAÇÃO DINÂMICA DAS APLICAÇÕES (NGO, DONATION, VOLUNTEER)
# ==========================================================
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
    # 🎯 CORRIGIDO: Apontando para o monorepo real
    repoURL: "https://github.com/fdaltro/hackathon.git"
    targetRevision: HEAD
    # 🎯 CORRIGIDO: O caminho precisa incluir a pasta solidary-gitops
    path: "solidary-gitops/apps/${each.key}"
    kustomize: {}
  destination:
    server: "https://kubernetes.default.svc"
    namespace: solidary
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
YAML

  depends_on = [helm_release.argocd]
}

# ==========================================================
# 4. CRIAÇÃO DA APLICAÇÃO DE INFRAESTRUTURA (Ingress + HPA)
# ==========================================================
resource "kubectl_manifest" "solidary_infra" {
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
    directory:
      recurse: true
  destination:
    server: "https://kubernetes.default.svc"
    namespace: solidary
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
YAML

  depends_on = [helm_release.argocd]
}