#!/bin/bash
set -e
NAMESPACE="logging"
APP_NAME="logging-stack"
cd /home/ondrejko_gulkas/mon

echo "=== OPRAVA VECTORA POMOCOU DATA STREAM ==="

# Dočasne vypneme auto-sync
kubectl patch application $APP_NAME -n argocd --type merge -p '{"spec":{"syncPolicy":null}}' 2>/dev/null || true

# Odstránime starú ConfigMap
kubectl delete configmap vector-config -n $NAMESPACE --ignore-not-found

# Vytvoríme novú so správnym data_stream
kubectl create configmap vector-config -n $NAMESPACE --from-literal=vector.yaml="
sources:
  all_logs:
    type: kubernetes_logs
    node_annotation_fields: {}
transforms:
  simple_remap:
    type: remap
    inputs: [\"all_logs\"]
    source: |
      .pod_name = .kubernetes.pod_name
      .namespace = .kubernetes.pod_namespace
      .status = \"repaired\"
sinks:
  es_out:
    type: elasticsearch
    inputs: [\"simple_remap\"]
    endpoints: [\"http://elasticsearch.logging:9200\"]
    mode: \"data_stream\"
    data_stream:
      type: \"logs\"
      dataset: \"lamp\"
      namespace: \"default\"
"

# Reštartujeme Vector
kubectl rollout restart daemonset vector -n $NAMESPACE
sleep 20

# Skontrolujeme logy (nemala by byť chyba)
echo "--- LOGY VECTORA PO OPRAVE ---"
kubectl logs -n $NAMESPACE -l app=vector --tail=20

# Vygenerujeme test log a počkáme
kubectl exec -n lamp deployment/apache-php -- curl -s http://localhost/ >/dev/null 2>&1 || true
sleep 10

# Skontrolujeme indexy
echo "--- INDEXY V ELASTICSEARCH ---"
kubectl exec -n $NAMESPACE deployment/elasticsearch -- curl -s "http://localhost:9200/_cat/indices?v" | grep "logs-lamp"

# Aktualizujeme Git - prepíšeme vector-configmap.yaml
cat > ansible/clusters/my-cluster/logging/vector-configmap.yaml << 'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: vector-config
  namespace: logging
data:
  vector.yaml: |
    sources:
      all_logs:
        type: kubernetes_logs
        node_annotation_fields: {}
    transforms:
      simple_remap:
        type: remap
        inputs: ["all_logs"]
        source: |
          .pod_name = .kubernetes.pod_name
          .namespace = .kubernetes.pod_namespace
          .status = "repaired"
    sinks:
      es_out:
        type: elasticsearch
        inputs: ["simple_remap"]
        endpoints: ["http://elasticsearch.logging:9200"]
        mode: "data_stream"
        data_stream:
          type: "logs"
          dataset: "lamp"
          namespace: "default"
YAML

# Commit a push
git add ansible/clusters/my-cluster/logging/vector-configmap.yaml
git commit -m "fix: vector data_stream instead of bulk index"
git push origin main

# Obnovíme auto-sync a vynútime refresh
kubectl patch application $APP_NAME -n argocd --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
kubectl annotate application $APP_NAME -n argocd argocd.argoproj.io/refresh=hard --overwrite

echo "=== HOTOVO - Indexy by sa mali vytvárať ako logs-lamp-* ==="
