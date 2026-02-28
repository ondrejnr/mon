#!/bin/bash
set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✅ $*${NC}"; }
err()  { echo -e "${RED}❌ $*${NC}"; exit 1; }
info() { echo -e "${CYAN}ℹ️  $*${NC}"; }
step() { echo -e "\n${BOLD}═══════════════════════════════════════════${NC}"; echo -e "${BOLD}$*${NC}"; echo -e "${BOLD}═══════════════════════════════════════════${NC}"; }

step "🔍 [0/9] KONTROLA PREREKVIZÍT"

for cmd in kubectl git curl; do
  command -v $cmd &>/dev/null && ok "$cmd dostupný" || err "$cmd chýba!"
done

kubectl get nodes &>/dev/null && ok "kubectl spojený s klastrom" || err "Klaster nedostupný"

info "Verzie nástrojov:"
kubectl version --client --short 2>/dev/null || kubectl version --client
git --version
curl --version | head -1

ok "Všetky prerekvizity splnené"
