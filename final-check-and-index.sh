#!/bin/bash
set -e
NAMESPACE="logging"
echo "=== FINÁLNA KONTROLA A NASTAVENIE INDEX PATTERN ==="

# 1. Vygenerujeme viac logov
echo "Generujem testovacie logy..."
for i in {1..10}; do
  kubectl exec -n lamp deployment/apache-php -- curl -s http://localhost/ >/dev/null 2>&1 || true
  sleep 1
done
sleep 10

# 2. Skontrolujeme, či sa vytvorili data stream indexy
echo "--- INDEXY V ELASTICSEARCH (data stream) ---"
INDICES=$(kubectl exec -n $NAMESPACE deployment/elasticsearch -- curl -s "http://localhost:9200/_cat/indices/.ds-logs-lamp-*?v" 2>/dev/null || true)
if [ -z "$INDICES" ]; then
  echo "❌ Data stream indexy sa ešte nevytvorili."
  echo "Skúšam manuálne vyhľadať všetky indexy:"
  kubectl exec -n $NAMESPACE deployment/elasticsearch -- curl -s "http://localhost:9200/_cat/indices?v" | grep -E "lamp|logs"
else
  echo "$INDICES"
fi

# 3. Ak existujú, nastavíme index pattern v Kibane
if [ -n "$INDICES" ]; then
  echo "--- NASTAVENIE INDEX PATTERN V KIBANE ---"
  # Získame presný názov index patternu (prvý riadok, stĺpec index)
  PATTERN=$(echo "$INDICES" | awk 'NR==2 {print $3}' | sed 's/^\.ds-//; s/-[0-9]*$//')
  if [ -z "$PATTERN" ]; then
    PATTERN="logs-lamp-*"
  fi
  echo "Používam pattern: $PATTERN"

  # Pošleme požiadavku do Kibana API na vytvorenie index pattern
  KIBANA_POD=$(kubectl get pods -n $NAMESPACE -l app=kibana -o jsonpath='{.items[0].metadata.name}')
  kubectl exec -n $NAMESPACE $KIBANA_POD -- curl -s -X POST "http://localhost:5601/api/saved_objects/index-pattern" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d "{\"attributes\":{\"title\":\"$PATTERN\",\"timeFieldName\":\"@timestamp\"}}" || echo "⚠️ Nepodarilo sa vytvoriť index pattern (možno už existuje)."
else
  echo "⚠️ Indexy zatiaľ nie sú, počkajte a skúste neskôr."
fi

echo "=== HOTOVO - Ak indexy existujú, v Kibane nájdete logy pod '$PATTERN' ==="
