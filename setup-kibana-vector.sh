#!/bin/bash
set -e
NAMESPACE="logging"
INDEX_PATTERN="logs-lamp-*"
TIMEFIELD="@timestamp"

echo "=== NASTAVENIE KIBANA PRE LOGY Z VECTORA ==="

# 1. Získať názov Kibana podu
KIBANA_POD=$(kubectl get pods -n $NAMESPACE -l app=kibana -o jsonpath='{.items[0].metadata.name}')
if [ -z "$KIBANA_POD" ]; then
    echo "❌ Kibana pod nenájdený"
    exit 1
fi
echo "✅ Kibana pod: $KIBANA_POD"

# 2. Overiť, či Elasticsearch beží a má indexy
echo "--- Kontrola indexov v Elasticsearch ---"
INDICES=$(kubectl exec -n $NAMESPACE deployment/elasticsearch -- curl -s "http://localhost:9200/_cat/indices/logs-lamp-*?h=index")
if [ -z "$INDICES" ]; then
    echo "❌ Žiadne indexy pre vzor $INDEX_PATTERN nenájdené. Počkajte na logy."
    exit 1
else
    echo "✅ Nájdené indexy:"
    echo "$INDICES" | head -5
fi

# 3. Vytvorenie index pattern v Kibane (ak neexistuje)
echo "--- Vytváram index pattern '$INDEX_PATTERN' ---"
# Najprv skúsime existujúce patterny
EXISTING=$(kubectl exec -n $NAMESPACE $KIBANA_POD -- curl -s "http://localhost:5601/api/saved_objects/_find?type=index-pattern" | grep -o "$INDEX_PATTERN" || true)
if [ -n "$EXISTING" ]; then
    echo "✅ Index pattern '$INDEX_PATTERN' už existuje."
else
    # Vytvorenie nového patternu
    RESPONSE=$(kubectl exec -n $NAMESPACE $KIBANA_POD -- curl -s -X POST "http://localhost:5601/api/saved_objects/index-pattern" \
        -H "kbn-xsrf: true" \
        -H "Content-Type: application/json" \
        -d "{\"attributes\":{\"title\":\"$INDEX_PATTERN\",\"timeFieldName\":\"$TIMEFIELD\"}}")
    if echo "$RESPONSE" | grep -q "error"; then
        echo "❌ Chyba pri vytváraní: $RESPONSE"
    else
        echo "✅ Index pattern vytvorený: $RESPONSE"
    fi
fi

# 4. Nastaviť ako východzí (voliteľné)
echo "--- Nastavujem ako východzí index pattern ---"
kubectl exec -n $NAMESPACE $KIBANA_POD -- curl -s -X POST "http://localhost:5601/api/kibana/settings/defaultIndex" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d "{\"value\":\"$INDEX_PATTERN\"}" || echo "⚠️ Nepodarilo sa nastaviť ako východzí"

# 5. Overenie v Discover
echo "--- Odkaz na Discover ---"
echo "Otvorte Kibanu na http://kibana.34.89.208.249.nip.io"
echo "Prejdite do Discover (vľavo hore) a vyberte index pattern '$INDEX_PATTERN'"
echo "Mali by ste vidieť logy z aplikácií."

echo "=== HOTOVO ==="
