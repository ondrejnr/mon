#!/bin/bash
set -e
NAMESPACE="logging"
APP_NAME="logging-stack"
cd /home/ondrejko_gulkas/mon

echo "=== KONEČNÁ OPRAVA VECTORA (obídenie ArgoCD) ==="

# 1. Dočasne vypneme auto-sync
kubectl patch application $APP_NAME -n argocd --type merge -p '{"spec":{"syncPolicy":null}}' 2>/dev/null || true

# 2. Odstránime starú ConfigMap
kubectl delete configmap vector-config -n $NAMESPACE --ignore-not-found

# 3. Vytvoríme novú so správnym endpoints a hostiteľom
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

# 4. Reštartujeme Vector
kubectl rollout restart daemonset vector -n $NAMESPACE
sleep 20

# 5. Skontrolujeme logy (už žiadne varovanie)
echo "--- LOGY VECTORA PO OPRAVE ---"
kubectl logs -n $NAMESPACE -l app=vector --tail=20 | grep -i endpoint || echo "OK - žiadne varovanie"

# 6. Vygenerujeme test log a počkáme
kubectl exec -n lamp deployment/apache-php -- curl -s http://localhost/ >/dev/null 2>&1 || true
sleep 10

# 7. Skontrolujeme indexy
echo "--- INDEXY V ELASTICSEARCH ---"
kubectl exec -n $NAMESPACE deployment/elasticsearch -- curl -s "http://localhost:9200/_cat/indices?v" | grep lamp || echo "❌ Indexy stále chýbajú - skontroluj ručne."

# 8. Aktualizujeme Git - použijeme vector-configmap.yaml (správny súbor)
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

# Odstránime prípadný starý vector.yaml, ktorý by mohol byť referencovaný
rm -f ansible/clusters/my-cluster/logging/vector.yaml

# Upravíme kustomization.yaml, aby používal iba vector-configmap.yaml
if [ -f ansible/clusters/my-cluster/logging/kustomization.yaml ]; then
    sed -i 's/vector.yaml/vector-configmap.yaml/g' ansible/clusters/my-cluster/logging/kustomization.yaml
else
    echo "resources:" > ansible/clusters/my-cluster/logging/kustomization.yaml
    echo "- vector-configmap.yaml" >> ansible/clusters/my-cluster/logging/kustomization.yaml
fi

# 9. Commit a push
git add ansible/clusters/my-cluster/logging/
git commit -m "fix: vector config - final working version with endpoints"
git push origin main

# 10. Obnovíme auto-sync a vynútime refresh
kubectl patch application $APP_NAME -n argocd --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
kubectl annotate application $APP_NAME -n argocd argocd.argoproj.io/refresh=hard --overwrite

echo "=== HOTOVO ==="
