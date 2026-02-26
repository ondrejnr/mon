#!/bin/bash
C_CYAN='\033[0;36m'
C_GOLD='\033[0;33m'
C_RED='\033[0;31m'
C_NC='\033[0m'

echo -e "${C_CYAN}>>> KOMPLEXNÝ AUDIT ODCHODZEJÚCEJ A PRICHÁDZAJÚCEJ PREVÁDZKY <<<${NC}"

# 1. KONTROLA BINÁRKY A PROCESOV NA NODE (Kto drží port 80/443?)
echo -e "\n${C_GOLD}[1] OS LEVEL: Kto počúva na porte 80/443?${NC}"
sudo netstat -tulpn | grep -E ":80|:443" || echo "ŽIADNY PROCES NEPOČÚVA NA PORTE 80/443!"

# 2. IDENTIFIKÁCIA NGINX V CLUSTRI (Hľadanie podľa reálneho obrazu, nie labelov)
echo -e "\n${C_GOLD}[2] K8S LEVEL: Hľadám Ingress Controller podľa obrazu (image)${NC}"
kubectl get pods -A -o json | jq -r '.items[] | select(.spec.containers[].image | contains("ingress-nginx")) | "Namespace: \(.metadata.namespace) | Pod: \(.metadata.name) | Status: \(.status.phase)"'

# 3. KONTROLA SERVICE LOADBALANCER (Verejná IP)
echo -e "\n${C_GOLD}[3] EXTERNAL ACCESS: Má Ingress Controller verejnú IP?${NC}"
kubectl get svc -A | grep -iE "ingress|lb|loadbalancer" | grep -v "admission"

# 4. TRACE: INGRESS -> ENDPOINTS (Prečo to končí na 404/503?)
echo -e "\n${C_GOLD}[4] ROUTING TRACE: Prepojenie na Backend${NC}"
kubectl get ing -A -o json | jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name) \(.spec.rules[0].host)"' | while read ns name host; do
    svc=$(kubectl get ing $name -n $ns -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}')
    eps=$(kubectl get endpoints $svc -n $ns -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)
    printf "Host: %-35s | Svc: %-15s | Endpoints: %-15s\n" "$host" "$svc" "$eps"
done

# 5. KONTROLA K3S CONFIG (Ak používaš k3s, hľadáme zakázaný Traefik)
echo -e "\n${C_GOLD}[5] K3S CONFIG: Je Traefik skutočne vypnutý?${NC}"
ps aux | grep k3s | grep -E "disable=traefik|disable traefik" && echo "Traefik je vypnutý v konfigurácii." || echo "VAROVANIE: Traefik nemusí byť korektne vypnutý!"

echo -e "\n${C_CYAN}>>> KONIEC AUDITU <<<${NC}"
