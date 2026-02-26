#!/bin/bash
C_CYAN='\033[0;36m'
C_GOLD='\033[0;33m'
C_RED='\033[0;31m'
C_NC='\033[0m'

echo -e "${C_CYAN}>>> ANALÝZA EXTERNÉHO NGINX LOADBALANCERA <<<${NC}"

# 1. KONTROLA EXERNEJ IP A PORTU
echo -e "\n${C_GOLD}[1] KONTROLA SERVICE LOADBALANCER (EXTERNAL IP)${NC}"
kubectl get svc -A | grep -E "ingress-nginx|traefik" | awk '{printf "%-20s %-20s %-15s %-20s\n", $1,$2,$5,$6}'

# 2. KONTROLA INGRESS CLASS (Kľúčové pre Nginx)
echo -e "\n${C_GOLD}[2] KONTROLA INGRESS CLASS (Kto obsluhuje Ingressy?)${NC}"
kubectl get ingressclass
kubectl get ing -A -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,CLASS:.spec.ingressClassName,HOST:.spec.rules[0].host"

# 3. NGINX INTERNAL ROUTING (Vidí Nginx pody v iných NS?)${NC}
echo -e "\n${C_GOLD}[3] NGINX BACKEND MAPPING${NC}"
NGINX_POD=$(kubectl get pods -A -l app.kubernetes.io/name=ingress-nginx -o jsonpath='{.items[0].metadata.name}')
NGINX_NS=$(kubectl get pods -A -l app.kubernetes.io/name=ingress-nginx -o jsonpath='{.items[0].metadata.namespace}')

if [ ! -z "$NGINX_POD" ]; then
    echo "Nginx Pod: $NGINX_POD"
    # Kontrola, či Nginx vidí IP adresy podov pre tvoj Apache a Grafanu
    kubectl exec -n $NGINX_NS $NGINX_POD -- /usr/bin/dbg dbg backends 2>/dev/null || \
    kubectl exec -n $NGINX_NS $NGINX_POD -- curl -s localhost:10246/configuration/backends | jq -r '.[] | select(.endpoints != null) | "Host: \(.name) | IP: \(.endpoints[].address):\(.endpoints[].port)"'
else
    echo -e "${C_RED}Nginx Pod nenájdený! Skontroluj inštaláciu.${NC}"
fi

# 4. KONTROLA LOGOV PRE "UPSTREAM NOT FOUND"
echo -e "\n${C_GOLD}[4] TRAFFIC REJECTION LOGS (Prečo ťa Argo vykoplo?)${NC}"
kubectl logs -n $NGINX_NS $NGINX_POD --tail=100 | grep -E "error|502|503|header" | tail -n 10

echo -e "\n${C_CYAN}>>> KONIEC AUDITU <<<${NC}"
