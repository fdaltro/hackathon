# ==========================================================
# KUBECOST - Visibilidade de Custos e Rightsizing (FinOps)
#
# Usa a distribuição oficial mantida em parceria entre AWS e
# Kubecost (public.ecr.aws/kubecost/cost-analyzer), disponível
# gratuitamente para clusters EKS sem precisar de token de
# cadastro no site da Kubecost (diferente do chart da comunidade
# em kubecost.github.io, que exige um kubecostToken).
#
# Isso resolve diretamente a limitação do AWS Academy de não ter
# o Cost Explorer completo liberado - o Kubecost calcula os
# custos por namespace/pod/label direto de dentro do cluster,
# usando a tabela de preços pública da AWS.
# ==========================================================

resource "kubernetes_namespace" "kubecost" {
  metadata {
    name = "kubecost"
  }
}

resource "helm_release" "kubecost" {
  name       = "kubecost"
  repository = "oci://public.ecr.aws/kubecost/cost-analyzer"
  chart      = "cost-analyzer"
  namespace  = kubernetes_namespace.kubecost.metadata[0].name
  timeout    = 600

  set {
    name  = "kubecostProductConfigs.clusterName"
    value = var.cluster_name
  }

  # ---------------------------------------------------------
  # FinOps: sem PVC, seguindo a mesma política já usada no
  # resto do projeto (Prometheus/Loki também rodam sem disco).
  # O Kubecost vem com seu próprio Prometheus dedicado por
  # padrão (recomendado pela própria Kubecost, evita conflito
  # de scrape config com o Prometheus geral de observabilidade).
  # ---------------------------------------------------------
  set {
    name  = "prometheus.server.persistentVolume.enabled"
    value = "false"
  }
  set {
    name  = "prometheus.alertmanager.persistentVolume.enabled"
    value = "false"
  }
  set {
    name  = "prometheus.server.persistentVolume.size"
    value = "2Gi"
  }

  # Retenção reduzida - ambiente de lab não precisa dos 15 dias
  # padrão, e isso reduz o consumo de memória/CPU no cluster.
  set {
    name  = "prometheus.server.retention"
    value = "3d"
  }

  # Recursos enxutos - cluster do AWS Academy tem capacidade limitada
  set {
    name  = "kubecostModel.resources.requests.cpu"
    value = "100m"
  }
  set {
    name  = "kubecostModel.resources.requests.memory"
    value = "256Mi"
  }
}
