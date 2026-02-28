#!/bin/bash
set -euo pipefail
GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✅ $*${NC}"; }
info() { echo -e "${CYAN}ℹ️  $*${NC}"; }
step() { echo -e "\n${BOLD}═══════════════════════════════════════════${NC}"; echo -e "${BOLD}$*${NC}"; echo -e "${BOLD}═══════════════════════════════════════════${NC}"; }

step "🌐 [1/9] INGRESS-NGINX"

# Odstránenie webhook ak existuje (predídeme konfliktom)
kubectl delete validatingwebhookconfigurations ingress-nginx-admission 2>/dev/null || true

# Inštalácia ingress-nginx
info "Inštalujem ingress-nginx..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.4/deploy/static/provider/cloud/deploy.yaml

info "Čakám na ingress-nginx controller (max 120s)..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=ingress-nginx \
  --timeout=120s

# Nastavenie LoadBalancer / externalIPs
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null || \
          kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
info "Node IP: $NODE_IP"

kubectl patch svc ingress-nginx-controller -n ingress-nginx \
  -p "{\"spec\":{\"externalIPs\":[\"$NODE_IP\"]}}" 2>/dev/null || true

ok "ingress-nginx nainštalovaný"
kubectl get svc ingress-nginx-controller -n ingress-nginx
