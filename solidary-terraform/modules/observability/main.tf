# COMENTADO: Datadog não está em uso no momento (nenhum provider configurado)
# terraform {
#   required_providers {
#     datadog = {
#       source  = "datadog/datadog"
#       version = "~> 3.0"
#     }
#   }
# }

# ==========================================================
# 1. NAMESPACE
# ==========================================================
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "observabilidade"
  }
}

# ==========================================================
# 2. PROMETHEUS (Sem Alertmanager nativo e sem discos)
# ==========================================================
resource "helm_release" "prometheus" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  timeout    = 600

  set {
    name  = "server.extraFlags[0]"
    value = "web.enable-remote-write-receiver"
  }
  set {
    name  = "server.extraFlags[1]"
    value = "enable-feature=remote-write-receiver"
  }
  set {
    name  = "server.extraFlags[2]"
    value = "web.enable-lifecycle"
  }
  set {
    name  = "server.persistentVolume.enabled"
    value = "false"
  }
  set {
    name  = "alertmanager.enabled"
    value = "false"
  }
  set {
    name  = "service.type"
    value = "LoadBalancer"
  }
  set {
    name  = "pushgateway.persistentVolume.enabled"
    value = "false"
  }

  values = [
    yamlencode({
      serverFiles = {
        "alerting_rules.yml" = {
          groups = [
            {
              name = "solidary-rules"
              rules = [
                {
                  alert = "AltaTaxaErrosHTTP4xx"
                  expr  = "(sum(rate(http_server_duration_milliseconds_count{http_status_code=~\"4..\"}[5m])) by (job) / sum(rate(http_server_duration_milliseconds_count[5m])) by (job)) * 100 > 5"
                  for   = "3m"
                  labels = {
                    severity = "critical"
                    team     = "sre-solidary"
                  }
                  annotations = {
                    summary     = "Alta taxa de erros 4xx detectada no serviço: {{ $labels.job }}"
                    description = "O microsserviço {{ $labels.job }} está com uma taxa de erros HTTP 4xx de {{ $value | printf \"%.2f\" }}% nos últimos 3 minutos, ultrapassando o limite seguro de 5%."
                  }
                }
              ]
            }
          ]
        }
      }
    })
  ]
}

# ==========================================================
# 3. LOKI (Sem discos)
# ==========================================================
resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki-stack"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  timeout    = 600

  set {
    name  = "loki.persistence.enabled"
    value = "false"
  }
}

# ==========================================================
# 4. GRAFANA (Sem discos e com Fontes Injetadas)
# ==========================================================
resource "helm_release" "grafana" {
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  timeout    = 600

  set {
    name  = "persistence.enabled"
    value = "false"
  }
  set {
    name  = "adminPassword"
    value = "admin123"
  }
  set {
    name  = "service.type"
    value = "LoadBalancer"
  }

  values = [
    yamlencode({
      datasources = {
        "datasources.yaml" = {
          apiVersion = 1
          datasources = [
            { name = "Prometheus", type = "prometheus", url = "http://prometheus-server.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local", access = "proxy", isDefault = true },
            { name = "Loki", type = "loki", url = "http://loki.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:3100", access = "proxy" },
            { name = "Jaeger", type = "jaeger", url = "http://jaeger.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:16686", access = "proxy" }
          ]
        }
      }
    })
  ]
}

# ==========================================================
# 6. JAEGER (Backend de Traces - Em Memória)
# ==========================================================
resource "helm_release" "jaeger" {
  name       = "jaeger"
  repository = "https://jaegertracing.github.io/helm-charts"
  chart      = "jaeger"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  timeout    = 600

  set {
    name  = "allInOne.enabled"
    value = "true"
  }
  set {
    name  = "storage.type"
    value = "memory"
  }
}

# ==========================================================
# 7. OPENTELEMETRY COLLECTOR (Roteador Central Duplo)
# ==========================================================
resource "helm_release" "otel_collector" {
  name       = "otel-collector"
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  timeout    = 600
  depends_on = [helm_release.prometheus, helm_release.loki, helm_release.jaeger]

  set {
    name  = "image.repository"
    value = "otel/opentelemetry-collector-contrib"
  }
  set {
    name  = "fullnameOverride"
    value = "otel-collector"
  }
  set {
    name  = "image.tag"
    value = "0.104.0"
  }

  values = [
    yamlencode({
      mode = "deployment"
      config = {
        extensions = { health_check = { endpoint = "0.0.0.0:13133" } }
        receivers = { otlp = { protocols = { grpc = { endpoint = "0.0.0.0:4317" }, http = { endpoint = "0.0.0.0:4318" } } } }
        processors = {
          batch = { send_batch_size = 1000, timeout = "10s" }
          memory_limiter = { check_interval = "5s", limit_mib = 250, spike_limit_mib = 50 }
          resourcedetection = { detectors = ["env", "system"] }
        }
        exporters = {
          prometheusremotewrite = { endpoint = "http://prometheus-server.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:80/api/v1/write", tls = { insecure = true } }
          loki = { endpoint = "http://loki.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:3100/loki/api/v1/push" }
          "otlp/jaeger" = { endpoint = "jaeger.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:4317", tls = { insecure = true } }
        }
        service = {
          telemetry = { metrics = { level = "none" } }
          extensions = ["health_check"]
          pipelines = {
            metrics = { receivers = ["otlp"], processors = ["resourcedetection", "memory_limiter", "batch"], exporters = ["prometheusremotewrite"] }
            logs = { receivers = ["otlp"], processors = ["resourcedetection", "memory_limiter", "batch"], exporters = ["loki"] }
            traces = { receivers = ["otlp"], processors = ["resourcedetection", "memory_limiter", "batch"], exporters = ["otlp/jaeger"] }
          }
        }
      }
    })
  ]
}

# ==========================================================
# 8. METRICS SERVER (Habilita o 'kubectl top')
# ==========================================================
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  
  set {
    name  = "args[0]"
    value = "--kubelet-insecure-tls"
  }
}

# ===========================================================
# 9. DATADOG AGENT (Âncora de Infraestrutura & Receptor OTLP)
# COMENTADO: Datadog não está em uso no momento
# ===========================================================
# resource "helm_release" "datadog_agent" {
#   name       = "datadog"
#   repository = "https://helm.datadoghq.com"
#   chart      = "datadog"
#   namespace  = kubernetes_namespace.monitoring.metadata[0].name
#   timeout    = 600
#
#   set_sensitive { name = "datadog.apiKey", value = var.datadog_api_key }
#
#   set { name = "datadog.otlp.receiver.protocols.grpc.enabled", value = "true" }
#   set { name = "datadog.otlp.receiver.protocols.grpc.endpoint", value = "0.0.0.0:4317" }
#   set { name = "datadog.otlp.receiver.protocols.http.enabled", value = "true" }
#   set { name = "datadog.otlp.receiver.protocols.http.endpoint", value = "0.0.0.0:4318" }
#   set { name = "datadog.site", value = "datadoghq.com" }
#   set { name = "datadog.logs.enabled", value = "true" }
#   set { name = "datadog.logs.containerCollectAll", value = "true" }
#   set { name = "datadog.apm.portEnabled", value = "true" }
#   set { name = "clusterAgent.enabled", value = "true" }
#   set { name = "datadog.kubelet.tlsVerify", value = "false" }
# }

# COMENTADO: Datadog não está em uso no momento
# # ==========================================================
# # 10. ALERTA INTELIGENTE (Monitorando donation-service)
# # ==========================================================
# resource "datadog_monitor" "donation_service_5xx_alert" {
#   name    = "[SolidaryTech] Taxa de Erro HTTP 5xx Crítica - donation-service"
#   type    = "query alert"
#
#   message = "A taxa de erro HTTP 5xx do donation-service ultrapassou 5%. Acionando PagerDuty e canal de ChatOps. @pagerduty-Solidary @slack-solidary-alerts"
#
#   query = "sum(last_5m):count:http.server.duration{service:donation-service,http.status_code:5*}.as_rate() / count:http.server.duration{service:donation-service}.as_rate() > 0.05"
#
#   monitor_thresholds {
#     critical = 0.05
#     warning  = 0.02
#   }
#
#   notify_no_data   = false
#   evaluation_delay = 60
#
#   tags = ["env:production", "service:donation-service", "team:grupo12-fiap"]
# }
#
# # ==========================================================
# # 11. DASHBOARD DE OPERAÇÕES - SOLIDARY TECH
# # ==========================================================
# resource "datadog_dashboard" "solidary_dashboard" {
#   title       = "Solidary Tech - Dashboard de Operações (Grupo 12)"
#   description = "Painel consolidado de SRE e Observabilidade criado via Terraform"
#   layout_type = "ordered"
#
#   widget {
#     alert_graph_definition {
#       alert_id  = datadog_monitor.donation_service_5xx_alert.id
#       viz_type  = "timeseries"
#       title     = "Status do Alerta: Taxa de Erro HTTP 5xx (donation-service)"
#     }
#   }
#
#   widget {
#     timeseries_definition {
#       title = "Volume de Requisições - donation-service"
#
#       request {
#         formula { formula_expression = "query1" }
#         query {
#           metric_query {
#             name  = "query1"
#             query = "count:http.server.duration{service:donation-service}.as_rate()"
#           }
#         }
#         display_type = "line"
#       }
#     }
#   }
# }