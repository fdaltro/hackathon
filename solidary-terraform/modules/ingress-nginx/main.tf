# ==========================================================
# NGINX INGRESS CONTROLLER
#
# Necessário para que os recursos "Ingress" do Kubernetes
# (solidary-gitops/infrastructure/ingress.yaml) funcionem de
# verdade - sem um controller instalado, o Ingress fica "órfão"
# e nunca expõe nada externamente.
#
# ==========================================================

resource "kubernetes_namespace" "ingress_nginx" {
  metadata {
    name = "ingress-nginx"
  }
}

resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  namespace  = kubernetes_namespace.ingress_nginx.metadata[0].name
  timeout    = 600

  # O controller do Ingress PRECISA de um LoadBalancer (ou NodePort)
  # para receber tráfego externo de verdade - é o próprio propósito
  # dele, diferente do ArgoCD/Grafana onde isso era opcional.
  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  # Sem PVC - mesma política do resto do projeto
  set {
    name  = "controller.admissionWebhooks.enabled"
    value = "true"
  }

  set {
    name  = "controller.resources.requests.cpu"
    value = "100m"
  }
  set {
    name  = "controller.resources.requests.memory"
    value = "128Mi"
  }
}
