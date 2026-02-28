#!/bin/bash
set -euo pipefail
GREEN='\033[0;32m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✅ $*${NC}"; }
step() { echo -e "\n${BOLD}═══════════════════════════════════════════${NC}"; echo -e "${BOLD}$*${NC}"; echo -e "${BOLD}═══════════════════════════════════════════${NC}"; }

step "📁 [2/9] NAMESPACES"

for ns in lamp logging monitoring web web-stack argocd; do
  kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f -
  ok "Namespace $ns"
done
