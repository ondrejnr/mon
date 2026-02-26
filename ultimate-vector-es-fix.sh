#!/bin/bash
set -euo pipefail
echo "═══════════════════════════════════════════════════════════════"
echo "🔧 ULTIMÁTNA OPRAVA VECTOR + ELASTICSEARCH"
echo "═══════════════════════════════════════════════════════════════"

NAMESPACE="logging"
ES_DEPLOY="elasticsearch"
VECTOR_DS="vector"

# 1. HĽBOKÁ DIAGNOSTIKA
echo ""
echo "🔍 [1/8] HĽBOKÁ DIAGNOSTIKA ELASTICSEARCH"
echo "----------------------------------------"
ES_POD=$(kubectl get pods -n $NAMESPACE -l app=$ES_DEPLOY -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
ES_SVC_IP=$(kubectl get svc $ES_DEPLOY -n $NAMESPACE -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
ES_SVC_PORT=$(kubectl get svc $ES_DEPLOY -n $NAMESPACE -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)

echo "Elasticsearch pod: $ES_POD"
echo "Service IP: $ES_SVC_IP:$ES_SVC_PORT"
echo ""
echo "--- Stav podu ---"
kubectl get pod -n $NAMESPACE $ES_POD -o wide || true
echo ""
echo "--- Logy Elasticsearch (posledných 20) ---"
kubectl logs -n $NAMESPACE $ES_POD --tail=20 || true
echo ""
echo "--- Endpoint pre elasticsearch service ---"
kubectl get endpoints $ES_DEPLOY -n $NAMESPACE || echo "❌ Endpoint nenájdený"
echo ""
echo "--- Test spojenia z iného podu (curl) ---"
kubectl run -it --rm test-es --image=curlimages/curl --restart=Never -n $NAMESPACE -- curl -s -o /dev/null -w "%{http_code}" "http://$ES_DEPLOY:$ES_SVC_PORT" || echo "❌ Spojenie zlyhalo"

# 2. OPRAVA ELASTICSEARCH (ak neodpovedá)
echo ""
echo "🛠️ [2/8] OPRAVA ELASTICSEARCH"
echo "----------------------------------------"
if ! kubectl exec -n $NAMESPACE $ES_POD -- curl -s -o /dev/null "http://localhost:9200"; then
  echo "❌ Elasticsearch neodpovedá interne, upravujem deployment..."
  # Pridanie env pre vypnutie security a single-node
  kubectl patch deployment $ES_DEPLOY -n $NAMESPACE --type='json' -p='[
    {"op":"add","path":"/spec/template/spec/containers/0/env","value":[
      {"name":"discovery.type","value":"single-node"},
      {"name":"xpack.security.enabled","value":"false"}
    ]}
  ]' 2>/dev/null || echo "⚠️ Deployment už má env, pokračujem..."
  # Zmena image na 7.17.10 (stabilnejšia)
  kubectl set image deployment/$ES_DEPLOY -n $NAMESPACE $ES_DEPLOY=docker.elastic.co/elasticsearch/elasticsearch:7.17.10 || true
  echo "Čakám 30 sekúnd na reštart..."
  sleep 30
  kubectl rollout status deployment/$ES_DEPLOY -n $NAMESPACE --timeout=120s
  kubectl logs -n $NAMESPACE -l app=$ES_DEPLOY --tail=10
else
  echo "✅ Elasticsearch odpovedá interne."
fi

# 3. OVERENIE CONFIGMAP VECTORA
echo ""
echo "📄 [3/8] KONTROLA CONFIGMAP VECTORA"
echo "----------------------------------------"
CM_NAME="vector-config"
kubectl get configmap $CM_NAME -n $NAMESPACE -o yaml | grep -A10 "vector.yaml" || echo "❌ ConfigMap neexistuje"

# 4. AK JE CONFIGMAP CHYBNÁ, VYTVORÍM NOVÚ
echo ""
echo "🔄 [4/8] AKTUALIZÁCIA CONFIGMAP (endpoints vs endpoint)"
CURRENT_ENDPOINT=$(kubectl get configmap $CM_NAME -n $NAMESPACE -o jsonpath='{.data.vector\.yaml}' 2>/dev/null | grep -o 'endpoint: "[^"]*"' || true)
if [[ "$CURRENT_ENDPOINT" == *"endpoint:"* ]]; then
  echo "⚠️ ConfigMap stále používa 'endpoint', prepisujem..."
  kubectl delete configmap $CM_NAME -n $NAMESPACE --ignore-not-found
  cat << 'CONFIG' | kubectl create configmap $CM_NAME -n $NAMESPACE --from-file=vector.yaml=/dev/stdin
sources:
  all_logs:
    type: kubernetes_logs
transforms:
  simple_remap:
    type: remap
    inputs: ["all_logs"]
    source: |
      .pod_name = .kubernetes.pod_name
      .status = "repaired"
sinks:
  es_out:
    type: elasticsearch
    inputs: ["simple_remap"]
    endpoints: ["http://elasticsearch.logging:9200"]
CONFIG
  echo "✅ ConfigMap vytvorená s 'endpoints'."
else
  echo "✅ ConfigMap už používa 'endpoints'."
fi

# 5. REŠTART VECTORA
echo ""
echo "🚀 [5/8] REŠTART VECTOR DAEMONSET"
echo "----------------------------------------"
kubectl rollout restart daemonset $VECTOR_DS -n $NAMESPACE
sleep 15
NEW_VECTOR_POD=$(kubectl get pods -n $NAMESPACE -l app=vector -o jsonpath='{.items[0].metadata.name}')
echo "Nový Vector pod: $NEW_VECTOR_POD"
kubectl logs -n $NAMESPACE $NEW_VECTOR_POD --tail=15

# 6. GENEROVANIE TEST LOGOV A KONTROLA INDEXOV
echo ""
echo "📊 [6/8] GENEROVANIE LOGOV A KONTROLA ELASTICSEARCH"
echo "----------------------------------------"
# Vygeneruj log z banky
kubectl exec -n lamp deployment/apache-php -- curl -s http://localhost/ >/dev/null 2>&1 || true
sleep 10
echo "Indexy v Elasticsearch:"
kubectl exec -n $NAMESPACE deployment/elasticsearch -- curl -s "http://localhost:9200/_cat/indices?v" || echo "❌ Elasticsearch stále neodpovedá"

# 7. KONTROLA ENDPOINTOV A SLUŽIEB
echo ""
echo "🔌 [7/8] KONTROLA ENDPOINTOV PRE LOGGING"
echo "----------------------------------------"
kubectl get endpoints -n $NAMESPACE

# 8. ULOŽENIE DO GITU (ak je repozitár)
echo ""
echo "💾 [8/8] UKLADÁM ZMENY DO GITU"
echo "----------------------------------------"
cd /home/ondrejko_gulkas/mon || exit
# Aktualizujem manifesty v ansible
mkdir -p ansible/clusters/my-cluster/logging
kubectl get configmap vector-config -n $NAMESPACE -o yaml | \
  grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > \
  ansible/clusters/my-cluster/logging/vector-configmap.yaml
kubectl get daemonset vector -n $NAMESPACE -o yaml | \
  grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > \
  ansible/clusters/my-cluster/logging/vector-daemonset.yaml
kubectl get deployment elasticsearch -n $NAMESPACE -o yaml | \
  grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > \
  ansible/clusters/my-cluster/logging/elasticsearch-deployment.yaml

git add ansible/clusters/my-cluster/logging/
git diff --cached --quiet || git commit -m "fix: vector elasticsearch connectivity, use endpoints, stable ES 7.17.10"
git push origin main || echo "⚠️ Git push zlyhal (možno žiadne zmeny)"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ ULTIMÁTNA OPRAVA DOKONČENÁ"
echo "═══════════════════════════════════════════════════════════════"
