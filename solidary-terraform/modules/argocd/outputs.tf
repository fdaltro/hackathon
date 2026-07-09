# Busca o segredo gerado pelo Helm para pegar a senha
data "kubernetes_secret" "argocd_admin_pwd" {
  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = "argocd"
  }
  # Garante que ele só tente ler depois que o Helm terminar
  depends_on = [helm_release.argocd]
}

# ==========================================================
# Nota: o serviço "server.service.type" foi trocado para
# ClusterIP (ver main.tf). Sem um LoadBalancer real, não há
# hostname externo para expor aqui — o acesso à UI do ArgoCD
# é feito via port-forward:
#
#   kubectl port-forward svc/argocd-server -n argocd 8080:443
#
# E depois acesse: https://localhost:8080
# ==========================================================

output "argocd_access_instructions" {
  description = "Como acessar a UI do ArgoCD (service é ClusterIP, sem LB externo)"
  value       = "Rode: kubectl port-forward svc/argocd-server -n argocd 8080:443  e acesse https://localhost:8080"
}

output "argocd_password" {
  description = "Senha inicial do usuário admin"
  value       = data.kubernetes_secret.argocd_admin_pwd.data["password"]
  sensitive   = true # Protege a senha de aparecer no log comum
}