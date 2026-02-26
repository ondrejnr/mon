#!/bin/bash
echo "═══════════════════════════════════════════════════════════════"
echo "🔍 KONTROLA VECTOR - STAV A KOMUNIKÁCIA"
echo "═══════════════════════════════════════════════════════════════"

NAMESPACE="logging"

echo ""
echo "📦 [1/6] STAV VECTOR PODOV"
echo "----------------------------------------"
kubectl get pods -n $NAMESPACE -l app=vector -o wide

VECTOR_POD=$(kubectl get pods -n $NAMESPACE -l app=vector -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$VECTOR_POD" ]; then
  echo "❌ VECTOR POD NENÁJDENÝ!"
  exit 1
fi

echo ""
echo "📋 [2/6] LOGY VECTORA (posledných 20)"
echo "----------------------------------------"
kubectl logs -n $NAMESPACE $VECTOR_POD --tail=20

echo ""
echo "📄 [3/6] KONFIGURÁCIA VECTORA"
echo "----------------------------------------"
kubectl exec -n $NAMESPACE $VECTOR_POD -- cat /etc/vector/vector.yaml 2>/dev/null

echo ""
echo "🔌 [4/6] TESTOVANIE KONEKTIVITY NA ELASTICSEARCH"
echo "----------------------------------------"
ES_CLUSTER_IP=$(kubectl get svc elasticsearch -n $NAMESPACE -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
ES_PORT=$(kubectl get svc elasticsearch -n $NAMESPACE -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)

echo "Elasticsearch: $ES_CLUSTER_IP:$ES_PORT"
kubectl exec -n $NAMESPACE $VECTOR_POD -- curl -s "http://elasticsearch:9200/_cluster/health" 2>/dev/null | jq . 2>/dev/null || \
kubectl exec -n $NAMESPACE $VECTOR_POD -- wget -qO- "http://elasticsearch:9200/_cluster/health" 2>/dev/null | head -10

echo ""
echo "📊 [5/6] KTORÉ INDEXY ELASTICSEARCH VYTVORIL VECTOR"
echo "----------------------------------------"
kubectl exec -n $NAMESPACE $VECTOR_POD -- curl -s "http://elasticsearch:9200/_cat/indices?v" 2>/dev/null

echo ""
echo "📝 [6/6] TESTOVACÍ LOG - ČI VECTOR ZBERE LOG Z APACHE"
echo "----------------------------------------"
# Vygeneruj log do apache
kubectl exec -n lamp deployment/apache-php -- curl -s http://localhost/ 2>/dev/null >/dev/null
sleep 5
echo "Posledné logy v Elasticsearch:"
kubectl exec -n $NAMESPACE $VECTOR_POD -- curl -s "http://elasticsearch:9200/_search?q=kubernetes.pod_name:*apache*&size=3&pretty" 2>/dev/null | grep -E "message|pod_name" | head -10

echo ""
echo "✅ KONTROLA DOKONČENÁ"
