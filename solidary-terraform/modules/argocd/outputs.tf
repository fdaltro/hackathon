# Busca o segredo gerado pelo Helm para pegar a senha
data "kubernetes_secret" "argocd_admin_pwd" {
  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = "argocd"
  }
  # Garante que ele só tente ler depois que o Helm terminar
  depends_on = [helm_release.argocd]
}

# Busca o serviço para pegar o endereço do LoadBalancer
data "kubernetes_service" "argocd_server" {
  metadata {
    name      = "argocd-server"
    namespace = "argocd"
  }
  depends_on = [helm_release.argocd]
}

output "argocd_url" {
  description = "URL de acesso ao ArgoCD"
  value       = data.kubernetes_service.argocd_server.status[0].load_balancer[0].ingress[0].hostname
}

output "argocd_password" {
  description = "Senha inicial do usuário admin"
  value       = data.kubernetes_secret.argocd_admin_pwd.data["password"]
  sensitive   = true # Protege a senha de aparecer no log comum
}