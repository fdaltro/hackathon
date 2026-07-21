output "how_to_check_external_ip" {
  description = "Como pegar o endereço externo do Ingress Controller"
  value       = "kubectl get svc -n ingress-nginx ingress-nginx-controller"
}
