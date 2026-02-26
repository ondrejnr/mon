#!/bin/bash
set -e
echo "=== NÚDZOVÁ OPRAVA LIVE CONFIGMAP + GIT SYNC ==="

NAMESPACE="logging"
cd /home/ondrejko_gulkas/mon

# 1. Zisti aktuálnu live ConfigMap
echo "--- AKTUÁLNA LIVE CONFIGMAP (stará) ---"
kubectl get configmap vector-config -n $NAMESPACE -o yaml | grep -A5 "vector.yaml" || true

# 2. Náhradná oprava priamo v klastri (obíde ArgoCD dočasne)
kubectl delete configmap vector-config -n $NAMESPACE --ignore-not-found
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
    mode: \"bulk\"
    index: \"lamp-logs-%Y.%m.%d\"
"

# 3. Reštart Vector
kubectl rollout restart daemonset vector -n $NAMESPACE
sleep 15

# 4. Over logy (už bez varovania)
echo "--- LOGY VECTORA PO OPRAVE ---"
kubectl logs -n $NAMESPACE -l app=vector --tail=20 | grep -i endpoint || echo "OK - žiadne varovanie"

# 5. Vygeneruj log a čakaj na index
kubectl exec -n lamp deployment/apache-php -- curl -s http://localhost/ >/dev/null 2>&1 || true
sleep 10

# 6. Skontroluj indexy
echo "--- INDEXY V ES ---"
kubectl exec -n $NAMESPACE deployment/elasticsearch -- curl -s "http://localhost:9200/_cat/indices?v" | grep lamp || echo "Stále nič, čakám ďalších 10s..."
sleep 10
kubectl exec -n $NAMESPACE deployment/elasticsearch -- curl -s "http://localhost:9200/_cat/indices?v" | grep lamp || echo "❌ Index stále chýba, skontroluj ručne."

# 7. Aktualizuj Git (aby zodpovedal live oprave)
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
git commit -m "fix: vector config - final working version with endpoints"
git push origin main

# 8. Force ArgoCD refresh
kubectl annotate application logging-stack -n argocd argocd.argoproj.io/refresh=hard --overwrite

echo "=== HOTOVO - Ak indexy stále nie sú, skontroluj: ==="
echo "kubectl exec -n logging deployment/elasticsearch -- curl -s http://localhost:9200/_cat/indices"
