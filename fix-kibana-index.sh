#!/bin/bash
set -e
NAMESPACE="logging"

echo "=== OPRAVA KIBANA INDEX PATTERN PODĽA REÁLNYCH INDEXOV ==="

# 1. Zisti reálne názvy indexov v Elasticsearch
echo "--- Reálne indexy v Elasticsearch ---"
INDICES=$(kubectl exec -n $NAMESPACE deployment/elasticsearch -- curl -s "http://localhost:9200/_cat/indices/logs-lamp-*?h=index")
if [ -z "$INDICES" ]; then
    echo "❌ Žiadne indexy logs-lamp-* neexistujú!"
    echo "Skúšam vyhľadať všetky lamp indexy:"
    kubectl exec -n $NAMESPACE deployment/elasticsearch -- curl -s "http://localhost:9200/_cat/indices?v" | grep lamp
    exit 1
fi

FIRST_INDEX=$(echo "$INDICES" | head -1)
echo "✅ Prvý nájdený index: $FIRST_INDEX"

# 2. Odvodenie správneho názvu index pattern
if [[ "$FIRST_INDEX" =~ ^\.ds-(.+)-[0-9]{4}\.[0-9]{2}\.[0-9]{2} ]]; then
    PATTERN="${BASH_REMATCH[1]}*"
else
    PATTERN="logs-lamp-*"
fi
echo "🔍 Odvodený index pattern: $PATTERN"

# 3. Získanie Kibana podu
KIBANA_POD=$(kubectl get pods -n $NAMESPACE -l app=kibana -o jsonpath='{.items[0].metadata.name}')
if [ -z "$KIBANA_POD" ]; then
    echo "❌ Kibana pod nenájdený"
    exit 1
fi

# 4. Vytvorenie nového index pattern
echo "--- Vytváram index pattern '$PATTERN' ---"
RESPONSE=$(kubectl exec -n $NAMESPACE $KIBANA_POD -- curl -s -X POST "http://localhost:5601/api/saved_objects/index-pattern" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d "{\"attributes\":{\"title\":\"$PATTERN\",\"timeFieldName\":\"@timestamp\"}}")

if echo "$RESPONSE" | grep -q "error"; then
    echo "❌ Chyba: $RESPONSE"
else
    echo "✅ Index pattern vytvorený: $RESPONSE"
fi

echo "=== HOTOVO ==="
echo "Teraz obnovte stránku Kibany (F5) a choďte do Discover."
