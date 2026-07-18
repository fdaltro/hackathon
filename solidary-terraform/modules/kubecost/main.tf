# ==========================================================
# KUBECOST - Visibilidade de Custos e Rightsizing (FinOps)
# ==========================================================

resource "kubernetes_namespace" "kubecost" {
  metadata {
    name = "kubecost"
  }
}

resource "helm_release" "kubecost" {
  name       = "kubecost"
  repository = "oci://public.ecr.aws/kubecost"
  chart      = "cost-analyzer"
  version    = "2.3.0"
  namespace  = kubernetes_namespace.kubecost.metadata[0].name
  timeout    = 600

  set {
    name  = "kubecostProductConfigs.clusterName"
    value = var.cluster_name
  }

  # ---------------------------------------------------------
  # FinOps: Configurações para rodar sem persistência (Storage)
  # ---------------------------------------------------------
  
  # Desabilita PVC do Kubecost (evita erro de Unbound PersistentVolumeClaim)
  set {
    name  = "persistentVolume.enabled"
    value = "false"
  }

  # Desabilita PVC do Prometheus embutido
  set {
    name  = "prometheus.server.persistentVolume.enabled"
    value = "false"
  }
  
  # Habilita emptyDir para permitir o armazenamento efêmero
  set {
    name  = "prometheus.server.emptyDir.enabled"
    value = "true"
  }

  set {
    name  = "prometheus.alertmanager.persistentVolume.enabled"
    value = "false"
  }

  # Retenção reduzida para poupar memória/CPU
  set {
    name  = "prometheus.server.retention"
    value = "3d"
  }

  # Recursos enxutos para o AWS Academy
  set {
    name  = "kubecostModel.resources.requests.cpu"
    value = "100m"
  }
  set {
    name  = "kubecostModel.resources.requests.memory"
    value = "256Mi"
  }
  
  # Garante que o Prometheus global esteja habilitado
  set {
    name  = "global.prometheus.enabled"
    value = "true"
  }
}