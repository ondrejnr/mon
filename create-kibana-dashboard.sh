#!/bin/bash
set -e
NAMESPACE="logging"
INDEX_PATTERN="logs-lamp-*"
KIBANA_POD=$(kubectl get pods -n $NAMESPACE -l app=kibana -o jsonpath='{.items[0].metadata.name}')

echo "=== VYTVORENIE DASHBOARDU V KIBANE PRE LOGY Z VECTORA ==="

# 1. Overenie index pattern
EXISTING=$(kubectl exec -n $NAMESPACE $KIBANA_POD -- curl -s "http://localhost:5601/api/saved_objects/_find?type=index-pattern" | grep -o "$INDEX_PATTERN" || true)
if [ -z "$EXISTING" ]; then
    echo "❌ Index pattern '$INDEX_PATTERN' neexistuje. Najprv ho vytvor: ./setup-kibana-vector.sh"
    exit 1
fi

# 2. Vytvorenie jednoduchej vizualizácie (stĺpcový graf počtu logov za čas)
echo "--- Vytváram vizualizáciu 'Logs over time' ---"
VIS_JSON=$(cat <<JSON
{
  "attributes": {
    "title": "Logs over time",
    "visState": "{\"title\":\"Logs over time\",\"type\":\"histogram\",\"params\":{\"type\":\"histogram\",\"grid\":{\"categoryLines\":false,\"valueAxis\":null},\"categoryAxes\":[{\"id\":\"CategoryAxis-1\",\"type\":\"category\",\"position\":\"bottom\",\"show\":true,\"style\":{},\"scale\":{\"type\":\"linear\"},\"labels\":{\"show\":true,\"filter\":true,\"truncate\":100},\"title\":{}}],\"valueAxes\":[{\"id\":\"ValueAxis-1\",\"name\":\"LeftAxis-1\",\"type\":\"value\",\"position\":\"left\",\"show\":true,\"style\":{},\"scale\":{\"type\":\"linear\",\"mode\":\"normal\"},\"labels\":{\"show\":true,\"rotate\":0,\"filter\":false,\"truncate\":100},\"title\":{\"text\":\"Count\"}}],\"seriesParams\":[{\"show\":true,\"type\":\"histogram\",\"mode\":\"stacked\",\"data\":{\"label\":\"Count\",\"id\":\"1\"},\"valueAxis\":\"ValueAxis-1\",\"drawLinesBetweenPoints\":true,\"lineWidth\":2,\"showCircles\":true}],\"addTooltip\":true,\"addLegend\":true,\"legendPosition\":\"right\",\"times\":[],\"addTimeMarker\":false,\"orderBucketsBySum\":false},\"aggs\":[{\"id\":\"1\",\"enabled\":true,\"type\":\"count\",\"schema\":\"metric\",\"params\":{}},{\"id\":\"2\",\"enabled\":true,\"type\":\"date_histogram\",\"schema\":\"segment\",\"params\":{\"field\":\"@timestamp\",\"interval\":\"auto\",\"min_doc_count\":1,\"extended_bounds\":{},\"useNormalizedEsInterval\":true}}]}",
    "uiStateJSON": "{}",
    "description": "",
    "version": 1,
    "kibanaSavedObjectMeta": {
      "searchSourceJSON": "{\"index\":\"$INDEX_PATTERN\",\"query\":{\"language\":\"kuery\",\"query\":\"\"},\"filter\":[]}"
    }
  }
}
JSON
)

VIS_RESPONSE=$(kubectl exec -n $NAMESPACE $KIBANA_POD -- curl -s -X POST "http://localhost:5601/api/saved_objects/visualization" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d "$VIS_JSON")
VIS_ID=$(echo "$VIS_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -n "$VIS_ID" ]; then
    echo "✅ Vizualizácia vytvorená s ID: $VIS_ID"
else
    echo "❌ Vizualizácia sa nepodarila vytvoriť: $VIS_RESPONSE"
    exit 1
fi

# 3. Vytvorenie dashboardu s touto vizualizáciou
echo "--- Vytváram dashboard 'Logs Dashboard' ---"
PANEL_JSON=$(cat <<JSON
[
  {
    "version": "7.17.10",
    "gridData": {
      "x": 0,
      "y": 0,
      "w": 48,
      "h": 15,
      "i": "1"
    },
    "panelIndex": "1",
    "embeddableConfig": {},
    "panelRefName": "panel_0"
  }
]
JSON
)

DASH_JSON=$(cat <<JSON
{
  "attributes": {
    "title": "Logs Dashboard",
    "hits": 0,
    "description": "",
    "panelsJSON": "$PANEL_JSON",
    "optionsJSON": "{\"useMargins\":true,\"hidePanelTitles\":false}",
    "version": 1,
    "timeRestore": false,
    "kibanaSavedObjectMeta": {
      "searchSourceJSON": "{\"query\":{\"language\":\"kuery\",\"query\":\"\"},\"filter\":[]}"
    }
  },
  "references": [
    {
      "name": "panel_0",
      "type": "visualization",
      "id": "$VIS_ID"
    }
  ]
}
JSON
)

DASH_RESPONSE=$(kubectl exec -n $NAMESPACE $KIBANA_POD -- curl -s -X POST "http://localhost:5601/api/saved_objects/dashboard" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d "$DASH_JSON")

if echo "$DASH_RESPONSE" | grep -q '"id"'; then
    DASH_ID=$(echo "$DASH_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    echo "✅ Dashboard vytvorený s ID: $DASH_ID"
    echo "Otvorte v prehliadači: http://kibana.34.89.208.249.nip.io/app/dashboards#/view/$DASH_ID"
else
    echo "❌ Dashboard sa nepodarilo vytvoriť: $DASH_RESPONSE"
    echo "Môžete ho vytvoriť manuálne:"
    echo "1. Choďte na http://kibana.34.89.208.249.nip.io"
    echo "2. Dashboard → Create dashboard → Add → Vyberte vizualizáciu 'Logs over time'"
fi

echo "=== HOTOVO ==="
