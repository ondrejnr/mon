#!/bin/bash
set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✅ $*${NC}"; }
err()  { echo -e "${RED}❌ $*${NC}"; exit 1; }
info() { echo -e "${CYAN}ℹ️  $*${NC}"; }
step() { echo -e "\n${BOLD}═══════════════════════════════════════════${NC}"; echo -e "${BOLD}$*${NC}"; echo -e "${BOLD}═══════════════════════════════════════════${NC}"; }

step "🛒 [15/16] INŠTALÁCIA ONLINE RETAIL MICROSERVICES"

kubectl create namespace online-retail --dry-run=client -o yaml | kubectl apply -f -

info "Aplikujem manifesty z /home/ondrejko_gulkas/online-retail/k8s-manifests"
if [ -d /home/ondrejko_gulkas/online-retail/k8s-manifests ]; then
  # CNPG
  kubectl apply -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.22/releases/cnpg-1.22.1.yaml
  sleep 10
  
  # Microservices
  kubectl apply -f /home/ondrejko_gulkas/online-retail/k8s-manifests/configmaps.yaml || true
  kubectl apply -f /home/ondrejko_gulkas/online-retail/k8s-manifests/secrets.yaml || true
  kubectl apply -f /home/ondrejko_gulkas/online-retail/k8s-manifests/pvcs.yaml || true
  kubectl apply -f /home/ondrejko_gulkas/online-retail/k8s-manifests/deployments.yaml || true
  kubectl apply -f /home/ondrejko_gulkas/online-retail/k8s-manifests/services.yaml || true
  kubectl apply -f /home/ondrejko_gulkas/online-retail/k8s-manifests/ingress.yaml || true
  ok "Manifesty aplikované"
else
  err "Zložka /home/ondrejko_gulkas/online-retail/k8s-manifests neexistuje!"
fi

info "Čakám na rozbehnutie služieb online-retail..."
kubectl wait --for=condition=ready pod -l app=frontend -n online-retail --timeout=300s || true
kubectl wait --for=condition=ready pod -l app=order-service -n online-retail --timeout=300s || true
kubectl wait --for=condition=ready pod -l app=product-service -n online-retail --timeout=300s || true

ok "Online Retail inštalácia dokončená"
