#!/bin/bash
set -e
echo "=== FIX VECTOR CONFIG V GITE A ARGOCD ==="

cd /home/ondrejko_gulkas/mon

# Prepíš ConfigMap v Gite
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
        mode: "bulk"
        index: "lamp-logs-%Y.%m.%d"
YAML

git add ansible/clusters/my-cluster/logging/vector-configmap.yaml
git commit -m "fix: vector config - endpoints and correct ES host"
git push origin main

# Force ArgoCD refresh
kubectl annotate application logging-stack -n argocd argocd.argoproj.io/refresh=hard --overwrite

sleep 15

# Reštartuj Vector
kubectl rollout restart daemonset vector -n logging
sleep 20

# Over logy
echo "--- LOGY VECTORA ---"
kubectl logs -n logging -l app=vector --tail=20

# Vygeneruj test log
kubectl exec -n lamp deployment/apache-php -- curl -s http://localhost/ >/dev/null 2>&1 || true
sleep 5

# Skontroluj indexy
echo "--- INDEXY V ES ---"
kubectl exec -n logging deployment/elasticsearch -- curl -s "http://localhost:9200/_cat/indices?v" | grep lamp || echo "Zatiaľ žiadne indexy"

echo "=== HOTOVO ==="
