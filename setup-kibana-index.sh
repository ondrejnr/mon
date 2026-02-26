#!/bin/bash
echo "═══════════════════════════════════════════════════════════════"
echo "🔧 NASTAVENIE KIBANA INDEX PATTERN PRE LOGY Z VECTORA"
echo "═══════════════════════════════════════════════════════════════"

NAMESPACE="logging"
ES_SVC="elasticsearch"
KIBANA_SVC="kibana"

# 1. ZISTENIE INDEXOV V ELASTICSEARCH
echo ""
echo "📊 [1/4] ZISŤUJEM EXISTUJÚCE INDEXY V ELASTICSEARCH"
INDICES=$(kubectl exec -n $NAMESPACE deployment/$ES_SVC -- curl -s "http://localhost:9200/_cat/indices?h=index" 2>/dev/null | grep -v "^\.kibana" | head -10)
if [ -z "$INDICES" ]; then
    echo "❌ Žiadne indexy nenájdené. Generujem testovací log..."
    kubectl exec -n lamp deployment/apache-php -- curl -s http://localhost/ >/dev/null 2>&1
    sleep 5
    INDICES=$(kubectl exec -n $NAMESPACE deployment/$ES_SVC -- curl -s "http://localhost:9200/_cat/indices?h=index" 2>/dev/null | grep -v "^\.kibana" | head -10)
fi

if [ -z "$INDICES" ]; then
    echo "❌ Stále žiadne indexy. Elasticsearch pravdepodobne neprijíma dáta."
    exit 1
fi

echo "✅ Nájdené indexy:"
echo "$INDICES" | sed 's/^/   /'

# Zistenie názvu prvého indexu pre odvodenie pattern
FIRST_INDEX=$(echo "$INDICES" | head -1)
if [[ "$FIRST_INDEX" =~ ^(.+)-[0-9]{4}\.[0-9]{2}\.[0-9]{2}$ ]]; then
    PATTERN="${BASH_REMATCH[1]}-*"
else
    PATTERN="*"
fi
echo "🔍 Navrhovaný index pattern: $PATTERN"

# 2. ZISTENIE KIBANA SERVICE DETAIL
echo ""
echo "🔌 [2/4] ZISŤUJEM KIBANA SERVICE"
KIBANA_IP=$(kubectl get svc $KIBANA_SVC -n $NAMESPACE -o jsonpath='{.spec.clusterIP}')
KIBANA_PORT=$(kubectl get svc $KIBANA_SVC -n $NAMESPACE -o jsonpath='{.spec.ports[0].port}')
echo "Kibana interne: $KIBANA_IP:$KIBANA_PORT"

# 3. VYTVORENIE INDEX PATTERN CEZ KIBANA API
echo ""
echo "🔄 [3/4] VYTVÁRAM INDEX PATTERN CEZ KIBANA API"

# Použijeme dočasný pod s curl v rovnakom namespace
cat << 'APIEOF' | kubectl run -i --rm kibana-setup --image=curlimages/curl --restart=Never -n $NAMESPACE -- sh -c '
KIBANA_URL="http://kibana:5601"
# Počkaj na Kibana (ak práve štartuje)
sleep 5

# Over, či Kibana beží
curl -s -f "$KIBANA_URL/api/status" > /dev/null || { echo "Kibana nie je dostupná"; exit 1; }

# Vytvor index pattern pre logy
echo "Vytváram index pattern s názvom: '"$PATTERN"'..."
curl -s -X POST "$KIBANA_URL/api/saved_objects/index-pattern" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d "{
    \"attributes\": {
      \"title\": \"$PATTERN\",
      \"timeFieldName\": \"@timestamp\"
    }
  }" || echo "Chyba pri vytváraní (možno už existuje)"

# Overenie existujúcich index patternov
echo ""
echo "Existujúce index patterny:"
curl -s "$KIBANA_URL/api/saved_objects/_find?type=index-pattern" | jq .
' 2>/dev/null

if [ $? -eq 0 ]; then
    echo "✅ Index pattern nastavený."
else
    echo "⚠️ Nepodarilo sa automaticky nastaviť. Vytvor ho manuálne v Kibane:"
    echo "   - Prihlás sa do Kibany na http://kibana.34.89.208.249.nip.io"
    echo "   - Choď do Stack Management → Index Patterns"
    echo "   - Vytvor nový pattern s názvom '$PATTERN' a časovým poľom '@timestamp'"
fi

# 4. KONTROLA, ČI LOGY UŽ PRICHÁDZAJÚ
echo ""
echo "📈 [4/4] KONTROLA PRÍCHODU LOGOV (cez Elasticsearch)"
sleep 5
COUNT=$(kubectl exec -n $NAMESPACE deployment/$ES_SVC -- curl -s "http://localhost:9200/_count?q=*" | grep -o '"count":[0-9]*' | cut -d: -f2)
if [ -n "$COUNT" ] && [ "$COUNT" -gt 0 ]; then
    echo "✅ V Elasticsearch je $COUNT dokumentov. Logy sa ukladajú."
else
    echo "⚠️ V Elasticsearch nie sú žiadne dokumenty. Skontroluj Vector a Elasticsearch."
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ NASTAVENIE DOKONČENÉ"
echo "═══════════════════════════════════════════════════════════════"
