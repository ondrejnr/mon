#!/bin/bash
set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✅ $*${NC}"; }
err()  { echo -e "${RED}❌ $*${NC}"; exit 1; }
info() { echo -e "${CYAN}ℹ️  $*${NC}"; }
step() { echo -e "\n${BOLD}═══════════════════════════════════════════${NC}"; echo -e "${BOLD}$*${NC}"; echo -e "${BOLD}═══════════════════════════════════════════${NC}"; }

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

step "🚀 SPÚŠŤAM KOMPLETNU INŠTALÁCIU KLASTRA VŠETKÝCH KOMPONENTOV"
echo "Adresár skriptov: $SCRIPTS_DIR"
echo "Začiatok: $(date)"

STEPS=(
  "../00-prerekvizity.sh"
  "../01-ingress-nginx.sh"
  "../02-namespaces.sh"
  "../03-lamp.sh"
  "../04-logging.sh"
  "../05-monitoring.sh"
  "../06-web.sh"
  "../07-argocd.sh"
  "../08-kibana-finalize.sh"
  "../09-final-test.sh"
  "10-cassandra.sh"
  "11-clickhouse.sh"
  "12-influxdb.sh"
  "13-mongodb.sh"
  "14-kafka.sh"
  "15-online-retail.sh"
)

for script in "${STEPS[@]}"; do
  # Resolve path
  SCRIPT_PATH="$SCRIPTS_DIR/$script"
  
  if [ -f "$SCRIPT_PATH" ]; then
    step "▶️  Spúšťam: $(basename $script)"
    chmod +x "$SCRIPT_PATH"
    bash "$SCRIPT_PATH" || { err "Skript $script zlyhal! Oprav chybu a spusti znova od tohto kroku."; }
    ok "$(basename $script) dokončený"
  else
    err "Skript $SCRIPT_PATH neexistuje!"
  fi
done

step "🎉 ÚPLNÁ INŠTALÁCIA DOKONČENÁ - $(date)"
echo ""
echo "Dostupné weby:"
for url in bank.34.89.208.249.nip.io grafana.34.89.208.249.nip.io alertmanager.34.89.208.249.nip.io \
           prometheus.34.89.208.249.nip.io argocd.34.89.208.249.nip.io kibana.34.89.208.249.nip.io \
           nginx.34.89.208.249.nip.io web.34.89.208.249.nip.io \
           api.34.89.208.249.nip.io shop.34.89.208.249.nip.io graphql.34.89.208.249.nip.io; do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://$url 2>/dev/null || echo "000")
  [[ "$code" =~ ^(200|301|302)$ ]] && icon="✅" || icon="❌"
  echo "  $icon $code → http://$url"
done
