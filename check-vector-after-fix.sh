#!/bin/bash
echo "═══════════════════════════════════════════════════════════════"
echo "🔍 KONTROLA VECTORA PO OPRAVE - $(date)"
echo "═══════════════════════════════════════════════════════════════"

NAMESPACE="logging"
VECTOR_POD=$(kubectl get pods -n $NAMESPACE -l app=vector -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

echo ""
echo "📦 [1/6] STAV VECTOR PODOV"
echo "----------------------------------------"
kubectl get pods -n $NAMESPACE -l app=vector -o wide

if [ -z "$VECTOR_POD" ]; then
  echo "❌ VECTOR POD NENÁJDENÝ!"
  exit 1
fi

echo ""
echo "📋 [2/6] LOGY VECTORA (posledných 20)"
echo "----------------------------------------"
kubectl logs -n $NAMESPACE $VECTOR_POD --tail=20

echo ""
echo "📄 [3/6] AKTUÁLNA KONFIGURÁCIA VECTORA"
echo "----------------------------------------"
kubectl exec -n $NAMESPACE $VECTOR_POD -- cat /etc/vector/vector.yaml 2>/dev/null

echo ""
echo "🔌 [4/6] TESTOVANIE KONEKTIVITY NA ELASTICSEARCH"
echo "----------------------------------------"
kubectl exec -n $NAMESPACE $VECTOR_POD -- curl -s "http://elasticsearch.logging:9200/_cluster/health" 2>/dev/null | jq . 2>/dev/null || \
kubectl exec -n $NAMESPACE $VECTOR_POD -- wget -qO- "http://elasticsearch.logging:9200/_cluster/health" 2>/dev/null

echo ""
echo "📊 [5/6] INDEXY V ELASTICSEARCH"
echo "----------------------------------------"
kubectl exec -n $NAMESPACE deployment/elasticsearch -- curl -s "http://localhost:9200/_cat/indices?v" 2>/dev/null

echo ""
echo "📝 [6/6] TESTOVACÍ LOG - ČI VECTOR ZBERE LOG Z APACHE"
echo "----------------------------------------"
# Vygeneruj log
kubectl exec -n lamp deployment/apache-php -- curl -s http://localhost/ >/dev/null 2>&1
sleep 5

echo "Hľadám logy v Elasticsearch:"
kubectl exec -n $NAMESPACE deployment/elasticsearch -- curl -s "http://localhost:9200/_search?q=kubernetes.pod_name:*apache*&size=3&pretty" 2>/dev/null | \
  grep -E "kubernetes.pod_name|message" | head -10

echo ""
echo "✅ KONTROLA DOKONČENÁ"
