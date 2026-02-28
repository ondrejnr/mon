#!/bin/bash
set -euo pipefail
GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✅ $*${NC}"; }
err()  { echo -e "${RED}❌ $*${NC}"; }
info() { echo -e "${CYAN}ℹ️  $*${NC}"; }
step() { echo -e "\n${BOLD}═══════════════════════════════════════════${NC}"; echo -e "${BOLD}$*${NC}"; echo -e "${BOLD}═══════════════════════════════════════════${NC}"; }

step "🧪 [9/9] FINÁLNY TEST VŠETKÝCH SLUŽIEB"

echo ""
info "=== STAV PODOV ==="
kubectl get pods -A | grep -vE "Running|Completed" && echo "(vyššie sú pody nie v Running stave)" || ok "Všetky pody sú Running/Completed"

echo ""
info "=== ARGOCD APPS ==="
kubectl get applications -A -o custom-columns="NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status" 2>/dev/null || echo "ArgoCD apps nenájdené"

echo ""
info "=== HTTP TESTY ==="
PASS=0; FAIL=0
for url in \
  bank.34.89.208.249.nip.io \
  grafana.34.89.208.249.nip.io \
  alertmanager.34.89.208.249.nip.io \
  prometheus.34.89.208.249.nip.io \
  argocd.34.89.208.249.nip.io \
  kibana.34.89.208.249.nip.io \
  nginx.34.89.208.249.nip.io \
  web.34.89.208.249.nip.io; do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 8 http://$url 2>/dev/null || echo "000")
  if [[ "$code" =~ ^(200|301|302|401|403)$ ]]; then
    ok "$code → http://$url"
    PASS=$((PASS+1))
  else
    err "$code → http://$url"
    FAIL=$((FAIL+1))
  fi
done

echo ""
ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "N/A")
step "📋 SÚHRN"
echo "  Prešlo:    $PASS / $((PASS+FAIL)) webov"
echo "  Zlyhalo:   $FAIL / $((PASS+FAIL)) webov"
echo ""
echo "  ArgoCD → http://argocd.34.89.208.249.nip.io"
echo "    user: admin  |  pass: $ARGOCD_PASS"
echo "  Grafana → http://grafana.34.89.208.249.nip.io"
echo "    user: admin  |  pass: admin"
echo "  Kibana  → http://kibana.34.89.208.249.nip.io"
echo "    index pattern: lamp-logs-*"
