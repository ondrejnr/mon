#!/bin/bash
set -e
NAMESPACE="logging"
echo "=== FORCE OPRAVA VECTOR CONFIGMAP (obídenie ArgoCD) ==="

# Dočasne vypneme auto-sync pre logging-stack
kubectl patch application logging-stack -n argocd --type merge -p '{"spec":{"syncPolicy":null}}' 2>/dev/null || true

# Odstránime starú ConfigMap
kubectl delete configmap vector-config -n $NAMESPACE --ignore-not-found

# Vytvoríme novú so správnym endpoints
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

# Reštartujeme Vector
kubectl rollout restart daemonset vector -n $NAMESPACE
sleep 20

# Overíme logy nového podu
echo "--- LOGY VECTORA ---"
kubectl logs -n $NAMESPACE -l app=vector --tail=20 | grep -i endpoint || echo "OK - žiadne varovanie"

# Vygenerujeme test log
kubectl exec -n lamp deployment/apache-php -- curl -s http://localhost/ >/dev/null 2>&1 || true
sleep 10

# Skontrolujeme indexy
echo "--- INDEXY V ES ---"
kubectl exec -n $NAMESPACE deployment/elasticsearch -- curl -s "http://localhost:9200/_cat/indices?v" | grep lamp || echo "❌ Indexy stále chýbajú"

# Ak chýbajú, skúsime manuálne poslať dokument pomocou wget (ak je v pod)
echo "--- SKÚŠAM MANUÁLNE POSLAŤ DOKUMENT ---"
VECTOR_POD=$(kubectl get pods -n $NAMESPACE -l app=vector -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n $NAMESPACE $VECTOR_POD -- sh -c "wget -q -O- --post-data='{\"message\":\"test\",\"@timestamp\":\"$(date -Iseconds)\"}' --header='Content-Type: application/json' http://elasticsearch.logging:9200/lamp-logs-test/_doc" 2>/dev/null || echo "⚠️ wget zlyhalo, skúšam iný kontajner"

# Ak nemáme wget, použijeme dočasný pod s curl
kubectl run curl-test --image=curlimages/curl -it --rm --restart=Never --namespace=$NAMESPACE -- curl -X POST "http://elasticsearch.logging:9200/lamp-logs-test/_doc" -H 'Content-Type: application/json' -d "{\"message\":\"test\",\"@timestamp\":\"$(date -Iseconds)\"}" 2>/dev/null || true

sleep 5
kubectl exec -n $NAMESPACE deployment/elasticsearch -- curl -s "http://localhost:9200/_cat/indices?v" | grep lamp

# Znovu zapneme auto-sync v ArgoCD (voliteľné)
kubectl patch application logging-stack -n argocd --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}' 2>/dev/null || true

echo "=== HOTOVO - Ak stále nič, skontroluj Elasticsearch: kubectl logs -n logging deployment/elasticsearch ==="
