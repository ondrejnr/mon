#!/bin/bash
source /scripts/common.sh 2>/dev/null
log_section "5. OPRAVA MONITORINGU"

# node-exporter Service
if ! kubectl get service node-exporter -n monitoring >/dev/null 2>&1; then
    log_warn "node-exporter Service chýba - vytváram..."
    kubectl apply -f - <<NODEEXP
apiVersion: v1
kind: Service
metadata:
  name: node-exporter
  namespace: monitoring
spec:
  selector:
    app: node-exporter
  ports:
  - port: 9100
    targetPort: 9100
NODEEXP
    log_ok "node-exporter Service vytvorený"
else
    log_ok "node-exporter Service existuje"
fi

wait_for_pod "app=node-exporter" monitoring 60

# Oprav Prometheus ConfigMap
log_info "Aplikujem správny Prometheus ConfigMap..."
kubectl create configmap prometheus-config \
  --from-literal=prometheus.yml="global:
  scrape_interval: 15s
scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter.monitoring.svc.cluster.local:9100']
  - job_name: 'apache'
    static_configs:
      - targets: ['apache-php.lamp:9117']
  - job_name: 'phpfpm'
    static_configs:
      - targets: ['apache-php.lamp:9253']
  - job_name: 'postgresql'
    static_configs:
      - targets: ['postgresql.lamp:9187']
  - job_name: 'grafana'
    static_configs:
      - targets: ['grafana.monitoring:80']
" \
  -n monitoring \
  --dry-run=client -o yaml | kubectl apply -f -

log_info "Reštartujem Prometheus..."
kubectl rollout restart deployment prometheus -n monitoring
wait_for_deployment prometheus monitoring 120

log_info "Reštartujem Grafanu..."
kubectl rollout restart deployment grafana -n monitoring
wait_for_deployment grafana monitoring 120
