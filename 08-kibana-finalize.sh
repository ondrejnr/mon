#!/bin/bash
set -euo pipefail
GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✅ $*${NC}"; }
info() { echo -e "${CYAN}ℹ️  $*${NC}"; }
step() { echo -e "\n${BOLD}═══════════════════════════════════════════${NC}"; echo -e "${BOLD}$*${NC}"; echo -e "${BOLD}═══════════════════════════════════════════${NC}"; }

step "📊 [8/9] KIBANA FINALIZÁCIA + STABILIZÁCIA"

KIBANA_URL="http://kibana.34.89.208.249.nip.io"
NS="logging"

ES_POD=$(kubectl get pods -n $NS -l app=elasticsearch -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "$ES_POD" ]; then
  info "Nastavujem ES disk watermark..."
  kubectl exec -n $NS $ES_POD -- curl -s -X PUT http://localhost:9200/_cluster/settings \
    -H "Content-Type: application/json" \
    -d '{"transient":{"cluster.routing.allocation.disk.watermark.low":"85%","cluster.routing.allocation.disk.watermark.high":"90%","cluster.routing.allocation.disk.watermark.flood_stage":"95%"}}' \
    | python3 -c "import sys,json;d=json.load(sys.stdin);print('Watermark OK ✓' if d.get('acknowledged') else 'WARN: '+str(d))" 2>/dev/null || true
fi

info "Čakám na Kibanu (max 120s)..."
COUNT=0; MAX=24
until curl -s "$KIBANA_URL/api/status" 2>/dev/null | grep -q '"overall"'; do
  COUNT=$((COUNT+1))
  [ $COUNT -ge $MAX ] && { info "Kibana ešte nie je ready, pokračujem..."; break; }
  echo "  Čakám... ($((COUNT*5))s)"
  sleep 5
done

info "Vytváram Kibana index pattern lamp-logs-*..."
curl -s -X POST "$KIBANA_URL/api/saved_objects/index-pattern/lamp-logs-pattern" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d '{"attributes":{"title":"lamp-logs-*","timeFieldName":"@timestamp"}}' \
  2>/dev/null | python3 -c "
import sys,json
try:
  d=json.load(sys.stdin)
  print('✅ Index pattern OK: ' + str(d.get('id','')) if d.get('id') else '⚠️  ' + str(d.get('message','')))
except: print('⚠️  Kibana ešte nie je dostupná')
" || true

info "Generujem test log..."
kubectl exec -n lamp deployment/apache-php -- curl -s http://localhost/ >/dev/null 2>&1 || true
sleep 10

info "Kontrola ES indexov:"
kubectl exec -n $NS deployment/elasticsearch -- \
  curl -s "http://localhost:9200/_cat/indices?v" 2>/dev/null | grep -v "^$" || true

ok "Kibana finalizácia dokončená"
echo "  Kibana: $KIBANA_URL"
