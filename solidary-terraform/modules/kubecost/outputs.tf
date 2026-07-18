output "namespace" {
  description = "Namespace onde o Kubecost foi instalado"
  value       = kubernetes_namespace.kubecost.metadata[0].name
}

output "how_to_access" {
  description = "Como acessar a UI do Kubecost (sem LoadBalancer, por padrão)"
  value       = "kubectl port-forward -n kubecost deployment/kubecost-cost-analyzer 9090:9090  ->  depois acesse http://localhost:9090"
}

output "how_to_get_forecast" {
  description = "Onde encontrar o relatório de forecast de custos dentro da UI"
  value       = "Na UI do Kubecost: menu 'Reports' > 'Cost Allocation' (ou 'Monthly Cost' no menu principal) - permite exportar CSV/PNG para o relatório do Hackathon"
}
