terraform {
  required_providers {
    datadog = {
      source  = "datadog/datadog"
      version = "~> 3.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
  }
}

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
    name  = "pushgateway.persistentVolume.enabled"
    value = "false"
  }
  set {
    name  = "service.type"
    value = "LoadBalancer"
  }

  # DESLIGA O ALERTMANAGER DO HELM
  set {
    name  = "alertmanager.enabled"
    value = "false"
  }

  # APONTA PARA O ALERTMANAGER MANUAL
  set {
    name  = "server.alertmanagers[0].static_configs[0].targets[0]"
    value = "alertmanager-manual-svc.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:9093"
  }

  values = [
    yamlencode({
      serverFiles = {
        "alerting_rules.yml" = {
          groups = [
            {
              name = "slo-error-budget"
              rules = [
                {
                  alert = "SLOFastBurn"
                  expr  = "sum(rate(http_server_duration_milliseconds_count{job=\"donation-service\", http_status_code=~\"5..\"}[1h])) / sum(rate(http_server_duration_milliseconds_count{job=\"donation-service\"}[1h])) > 0.0144"
                  for   = "5m"
                  labels = {
                    severity = "critical"
                    team     = "sre-solidary"
                  }
                  annotations = {
                    summary     = "Fast Burn Rate detectado!"
                    description = "O donation-service está consumindo o Error Budget 14.4x mais rápido que o normal. Risco de esgotamento total em 2 dias."
                  }
                },
                {
                  alert = "SLOSlowBurn"
                  expr  = "sum(rate(http_server_duration_milliseconds_count{job=\"donation-service\", http_status_code=~\"5..\"}[6h])) / sum(rate(http_server_duration_milliseconds_count{job=\"donation-service\"}[6h])) > 0.006"
                  for   = "15m"
                  labels = {
                    severity = "warning"
                    team     = "sre-solidary"
                  }
                  annotations = {
                    summary     = "Slow Burn Rate detectado."
                    description = "O donation-service está consumindo o Error Budget 6x mais rápido que o normal ao longo de 6 horas."
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
# 4. GRAFANA (Sem discos e com Fontes/Dashboards Injetados)
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
      dashboardProviders = {
        "dashboardproviders.yaml" = {
          apiVersion = 1
          providers = [
            {
              name            = "default"
              orgId           = 1
              folder          = ""
              type            = "file"
              disableDeletion = false
              editable        = true
              options = {
                path = "/var/lib/grafana/dashboards/default"
              }
            }
          ]
        }
      }
      dashboards = {
        default = {
          "slo-dashboard" = {
            json = tostring(jsonencode({
              title = "SLO & Error Budget - Donation Service"
              refresh = "10s"
              panels = [
                {
                  title = "SLO de Disponibilidade (Alvo: 99.9% em 30d)"
                  type = "gauge"
                  gridPos = { h = 8, w = 12, x = 0, y = 0 }
                  targets = [ { expr = "sum(rate(http_server_duration_milliseconds_count{job=\"donation-service\", http_status_code!~\"5..\"}[30d])) / sum(rate(http_server_duration_milliseconds_count{job=\"donation-service\"}[30d])) * 100", refId = "A", instant = true } ]
                  fieldConfig = { defaults = { min = 99.0, max = 100.0, unit = "percent", thresholds = { mode = "absolute", steps = [ { color = "red", value = null }, { color = "yellow", value = 99.5 }, { color = "green", value = 99.9 } ] } } }
                },
                {
                  title = "Error Budget Consumido (Janela: 30d, Limite: 0.1% falhas)"
                  type = "stat"
                  gridPos = { h = 8, w = 12, x = 12, y = 0 }
                  targets = [ { expr = "((sum(rate(http_server_duration_milliseconds_count{job=\"donation-service\", http_status_code=~\"5..\"}[30d])) or vector(0)) / sum(rate(http_server_duration_milliseconds_count{job=\"donation-service\"}[30d]))) / 0.001 * 100", refId = "A", instant = true } ]
                  fieldConfig = { defaults = { min = 0, max = 100, unit = "percent", thresholds = { mode = "absolute", steps = [ { color = "green", value = null }, { color = "yellow", value = 75 }, { color = "red", value = 100 } ] } } }
                },
                {
                  title = "Burn Rate (Sucesso vs Falhas 5xx) - donation-service"
                  type = "timeseries"
                  gridPos = { h = 8, w = 8, x = 0, y = 8 }
                  targets = [ 
                    { expr = "sum(rate(http_server_duration_milliseconds_count{job=\"donation-service\", http_status_code!~\"5..\"}[1m])) or vector(0)", legendFormat = "Sucesso", refId = "A" },
                    { expr = "sum(rate(http_server_duration_milliseconds_count{job=\"donation-service\", http_status_code=~\"5..\"}[1m])) or vector(0)", legendFormat = "Falhas 5xx", refId = "B" }
                  ]
                  fieldConfig = { defaults = { color = { mode = "palette-classic" } }, overrides = [ { matcher = { id = "byNames", options = "Falhas 5xx" }, properties = [ { id = "color", value = { fixedColor = "red", mode = "fixed" } } ] } ] }
                },
                {
                  title = "Latência P95 (Alvo: < 250ms) - donation-service"
                  type = "stat"
                  gridPos = { h = 8, w = 8, x = 8, y = 8 }
                  targets = [ { expr = "histogram_quantile(0.95, sum(rate(http_server_duration_milliseconds_bucket{job=\"donation-service\"}[5m])) by (le))", refId = "A", instant = true } ]
                  fieldConfig = { defaults = { unit = "ms", thresholds = { mode = "absolute", steps = [ { color = "green", value = null }, { color = "yellow", value = 200 }, { color = "red", value = 250 } ] } } }
                },
                {
                  title = "Saturação (Uso de CPU dos Pods)"
                  type = "timeseries"
                  gridPos = { h = 8, w = 8, x = 16, y = 8 }
                  targets = [ { expr = "sum(rate(container_cpu_usage_seconds_total{namespace=\"solidary\", pod!=\"\"}[1m])) by (pod)", legendFormat = "{{pod}}", refId = "A" } ]
                  fieldConfig = { defaults = { unit = "percentunit" } }
                }
              ]
            }))
          }
        }
      }
    })
  ]
}

# ==========================================================
# 5. ALERTMANAGER MANUAL (Solução de Contorno)
# ==========================================================
resource "kubernetes_config_map" "alertmanager_config" {
  metadata {
    name      = "prometheus-alertmanager"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    "alertmanager.yml" = yamlencode({
      global = {
        resolve_timeout = "5m"
      }
      route = {
        group_by        = ["alertname", "job"]
        group_wait      = "10s"
        group_interval  = "10s"
        repeat_interval = "1h"
        receiver        = "pagerduty-solidary" 
      }
      receivers = [
        {
          name = "pagerduty-solidary"
          pagerduty_configs = [
            {
              service_key   = var.pagerduty_integration_key
              send_resolved = true
              client        = "Prometheus Alertmanager (AWS Academy)"
              description   = "Alerta Prometheus: {{ .CommonAnnotations.summary }}"
              severity      = "{{ if eq .CommonLabels.severity \"critical\" }}critical{{ else }}warning{{ end }}"
            }
          ]
        }
      ]
    })
  }
}

resource "kubernetes_deployment" "alertmanager_manual" {
  depends_on = [kubernetes_config_map.alertmanager_config]

  metadata {
    name      = "alertmanager-manual"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    labels = {
      app = "alertmanager-manual"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "alertmanager-manual"
      }
    }

    template {
      metadata {
        labels = {
          app = "alertmanager-manual"
        }
      }

      spec {
        container {
          name  = "alertmanager"
          image = "quay.io/prometheus/alertmanager:v0.32.1"
          args  = [
            "--config.file=/etc/alertmanager/alertmanager.yml",
            "--storage.path=/alertmanager"
          ]

          port {
            container_port = 9093
            name           = "http"
          }

          volume_mount {
            name       = "config-volume"
            mount_path = "/etc/alertmanager"
          }

          volume_mount {
            name       = "storage-volume"
            mount_path = "/alertmanager"
          }
        }

        volume {
          name = "config-volume"
          config_map {
            name = "prometheus-alertmanager"
          }
        }

        volume {
          name = "storage-volume"
          empty_dir {}
        }
      }
    }
  }
}

resource "kubernetes_service" "alertmanager_manual_svc" {
  metadata {
    name      = "alertmanager-manual-svc"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  spec {
    selector = {
      app = "alertmanager-manual"
    }

    port {
      port        = 9093
      target_port = 9093
      name        = "http"
    }

    type = "ClusterIP"
  }
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
          datadog = {
            api = { key = var.datadog_api_key, site = var.datadog_site }
            metrics = { endpoint = "http://datadog.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:4318" }
          }
        }
        service = {
          telemetry = { metrics = { level = "none" } }
          extensions = ["health_check"]
          pipelines = {
            metrics = { receivers = ["otlp"], processors = ["resourcedetection", "memory_limiter", "batch"], exporters = ["prometheusremotewrite", "datadog"] }
            logs = { receivers = ["otlp"], processors = ["resourcedetection", "memory_limiter", "batch"], exporters = ["loki"] }
            traces = { receivers = ["otlp"], processors = ["resourcedetection", "memory_limiter", "batch"], exporters = ["otlp/jaeger", "datadog"] }
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
# ===========================================================
resource "helm_release" "datadog_agent" {
  name       = "datadog"
  repository = "https://helm.datadoghq.com"
  chart      = "datadog"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  timeout    = 600

  set_sensitive {
    name  = "datadog.apiKey"
    value = var.datadog_api_key
  }

  set {
    name  = "datadog.otlp.receiver.protocols.grpc.enabled"
    value = "true"
  }

  set {
    name  = "datadog.otlp.receiver.protocols.grpc.endpoint"
    value = "0.0.0.0:4317"
  }

  set {
    name  = "datadog.otlp.receiver.protocols.http.enabled"
    value = "true"
  }

  set {
    name  = "datadog.otlp.receiver.protocols.http.endpoint"
    value = "0.0.0.0:4318"
  }

  set {
    name  = "datadog.site"
    value = var.datadog_site
  }

  set {
    name  = "datadog.logs.enabled"
    value = "true"
  }

  set {
    name  = "datadog.logs.containerCollectAll"
    value = "true"
  }

  set {
    name  = "datadog.apm.portEnabled"
    value = "true"
  }

  set {
    name  = "clusterAgent.enabled"
    value = "true"
  }

  set {
    name  = "datadog.kubelet.tlsVerify"
    value = "false"
  }
}
# COMENTADO: Datadog não está em uso no momento
# # ===========================================================
# # 10. ALERTA INTELIGENTE (Monitorando donation-service)
# # ===========================================================
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
