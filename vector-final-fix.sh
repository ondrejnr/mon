#!/bin/bash
set -e
echo "═══════════════════════════════════════════════════════════════"
echo "🔧 FINÁLNA OPRAVA VECTORA PRE ELASTICSEARCH"
echo "═══════════════════════════════════════════════════════════════"

NAMESPACE="logging"
ES_SERVICE="elasticsearch"

echo ""
echo "📁 [1/6] OVERUJEM, ČI ELASTICSEARCH BEŽÍ A JE DOSTUPNÝ"
if kubectl get pods -n $NAMESPACE -l app=$ES_SERVICE | grep -q Running; then
  echo "✅ Elasticsearch pod beží"
else
  echo "❌ Elasticsearch pod NEBEŽÍ! Najskôr ho treba spustiť."
  exit 1
fi

ES_IP=$(kubectl get svc $ES_SERVICE -n $NAMESPACE -o jsonpath='{.spec.clusterIP}')
ES_PORT=$(kubectl get svc $ES_SERVICE -n $NAMESPACE -o jsonpath='{.spec.ports[0].port}')
echo "   Elasticsearch service: $ES_IP:$ES_PORT"
echo "   Testovanie spojenia z clusteru:"
kubectl run -it --rm test-es --image=curlimages/curl --restart=Never -n $NAMESPACE -- curl -s "http://$ES_SERVICE:$ES_PORT/_cluster/health" && echo "   ✅ ES odpovedá" || echo "   ❌ ES neodpovedá"

echo ""
echo "📁 [2/6] KONTROLUJEM AKTUÁLNU CONFIGMAP"
kubectl get configmap vector-config -n $NAMESPACE -o yaml | grep -A10 "vector.yaml" || echo "Configmap neexistuje"

echo ""
echo "📁 [3/6] AK NIE JE CONFIGMAP SPRÁVNA, VYTVORÍM NOVÚ SO SPRÁVNYM ENDPOINTS"
kubectl delete configmap vector-config -n $NAMESPACE --ignore-not-found=true

cat << 'CONFIG' | kubectl create configmap vector-config -n $NAMESPACE --from-file=vector.yaml=/dev/stdin
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

if [ $? -eq 0 ]; then
  echo "✅ Nová ConfigMap vytvorená s parametrom 'endpoints'"
else
  echo "❌ Nepodarilo sa vytvoriť ConfigMap"
  exit 1
fi

echo ""
echo "📁 [4/6] REŠTARTUJEM VECTOR DAEMONSET, ABY NAČÍTAL NOVÚ KONFIGURÁCIU"
kubectl rollout restart daemonset vector -n $NAMESPACE
sleep 10

echo ""
echo "📁 [5/6] KONTROLA LOGOV NOVÉHO VECTOR PODU"
NEW_VECTOR_POD=$(kubectl get pods -n $NAMESPACE -l app=vector -o jsonpath='{.items[0].metadata.name}')
echo "Nový Vector pod: $NEW_VECTOR_POD"
kubectl logs -n $NAMESPACE $NEW_VECTOR_POD --tail=15

echo ""
echo "📁 [6/6] KONTROLA, ČI ELASTICSEARCH UŽ MÁ NEJAKÉ INDEXY"
sleep 5
echo "Indexy v Elasticsearch:"
kubectl exec -n $NAMESPACE deployment/elasticsearch -- curl -s "http://localhost:9200/_cat/indices?v" || echo "Zatiaľ žiadne indexy"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ OPRAVA DOKONČENÁ - SLEDUJTE VÝSTUP"
echo "═══════════════════════════════════════════════════════════════"
