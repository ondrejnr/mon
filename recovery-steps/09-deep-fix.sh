#!/bin/bash
set -e
echo "═══════════════════════════════════════════════════════════════"
echo "🔧 HĽBOKÁ OPRAVA PO OB N OVE"
echo "═══════════════════════════════════════════════════════════════"

# 1. KONTROLA ARGOCD
echo ""
echo "📦 [1/5] ARGOCD - diagnostika a oprava"
kubectl get pods -n argocd | grep argocd-server || echo "❌ argocd-server neexistuje"

# Ak neexistuje, skúsime reštartovať deployment (možno je zastavený)
if ! kubectl get deployment argocd-server -n argocd &>/dev/null; then
    echo "Deployment argocd-server neexistuje. Spúšťam znova 06-setup-argocd.sh"
    /home/ondrejko_gulkas/mon/recovery-steps/06-setup-argocd.sh
else
    # Reštart pre istotu
    kubectl rollout restart deployment/argocd-server -n argocd
    sleep 20
fi

# Overenie ingress
echo "Ingress pre ArgoCD:"
kubectl get ingress -n argocd argocd-final -o yaml | grep -A5 "rules:" || echo "❌ Ingress neexistuje"

# 2. KONTROLA BANKY (503)
echo ""
echo "🏦 [2/5] BANKA - diagnostika a oprava"
POD=$(kubectl get pods -n lamp -l app=apache-php -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$POD" ]; then
    echo "❌ Pod banky neexistuje. Spúšťam 03-setup-lamp.sh"
    /home/ondrejko_gulkas/mon/recovery-steps/03-setup-lamp.sh
    sleep 10
    POD=$(kubectl get pods -n lamp -l app=apache-php -o jsonpath='{.items[0].metadata.name}')
fi

# Zisti stav podu
STATUS=$(kubectl get pod -n lamp $POD -o jsonpath='{.status.phase}')
echo "Pod $POD je v stave $STATUS"
if [ "$STATUS" != "Running" ]; then
    echo "❌ Pod nie je Running, logy:"
    kubectl logs -n lamp $POD --all-containers --tail=20
    exit 1
fi

# Skontroluj, či je Apache pripravený
READY=$(kubectl get pod -n lamp $POD -o jsonpath='{.status.containerStatuses[?(@.name=="apache")].ready}')
if [ "$READY" != "true" ]; then
    echo "❌ Apache kontajner nie je ready. Reštartujem pod?"
    kubectl delete pod -n lamp $POD
    sleep 20
    POD=$(kubectl get pods -n lamp -l app=apache-php -o jsonpath='{.items[0].metadata.name}')
fi

# Aplikujeme fix pre banku (ak ešte nebol)
if ! kubectl get configmap -n lamp apache-php-config &>/dev/null; then
    echo "Aplikujem 03-fix-lamp.sh"
    /home/ondrejko_gulkas/mon/recovery-steps/03-fix-lamp.sh
fi

# 3. KONTROLA PROMETHEUS (targets)
echo ""
echo "📈 [3/5] PROMETHEUS - konfigurácia scrape"
# Získať aktuálnu configmap
CM=$(kubectl get configmap -n monitoring prometheus-config -o yaml 2>/dev/null || true)
if [ -z "$CM" ]; then
    echo "❌ Prometheus config neexistuje. Vytváram základnú konfiguráciu."
    cat << 'PROM' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: monitoring
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
    scrape_configs:
      - job_name: 'kubernetes-pods'
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
            action: keep
            regex: true
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
            action: replace
            target_label: __metrics_path__
            regex: (.+)
          - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
            action: replace
            regex: ([^:]+)(?::\d+)?;(\d+)
            replacement: \$1:\$2
            target_label: __address__
PROM
else
    # Overíme, či obsahuje kubernetes_sd_configs
    if ! echo "$CM" | grep -q "kubernetes_sd_configs"; then
        echo "⚠️ Prometheus config neobsahuje Kubernetes SD. Aktualizujem."
        kubectl delete configmap prometheus-config -n monitoring
        kubectl create configmap prometheus-config -n monitoring --from-literal=prometheus.yml="
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: 'kubernetes-pods'
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
      - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        regex: ([^:]+)(?::\d+)?;(\d+)
        replacement: \$1:\$2
        target_label: __address__
"
    fi
fi

# Reštart prometheus pre načítanie configu
kubectl rollout restart deployment/prometheus -n monitoring
sleep 15

# 4. KONTROLA GRAFANA (no data)
echo ""
echo "📊 [4/5] GRAFANA - kontrola pripojenia k Prometheus"
GRAFANA_POD=$(kubectl get pods -n monitoring -l app=grafana -o jsonpath='{.items[0].metadata.name}')
if [ -n "$GRAFANA_POD" ]; then
    # Overíme, či je datasource nastavený
    # Pre jednoduchosť reštartujeme grafana (ak je problém)
    kubectl rollout restart deployment/grafana -n monitoring
    sleep 10
else
    echo "❌ Grafana pod neexistuje. Skús znova 04-setup-monitoring.sh"
fi

# 5. ZÁVEREČNÝ TEST
echo ""
echo "🌐 [5/5] ZÁVEREČNÝ TEST VŠETKÝCH WEBOV"
for url in bank.34.89.208.249.nip.io argocd.34.89.208.249.nip.io grafana.34.89.208.249.nip.io alertmanager.34.89.208.249.nip.io kibana.34.89.208.249.nip.io prometheus.34.89.208.249.nip.io web.34.89.208.249.nip.io nginx.34.89.208.249.nip.io; do
    echo -n "http://$url ... "
    curl -s -o /dev/null -w "%{http_code}\n" --max-time 10 http://$url || echo "timeout"
done

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ OPRAVA DOKONČENÁ"
echo "═══════════════════════════════════════════════════════════════"
