#!/bin/bash
# --- Širokospektrálna analýza Kubernetes Služieb ---
C_CYAN='\033[0;36m'
C_GOLD='\033[0;33m'
C_RED='\033[0;31m'
C_NC='\033[0m'

echo -e "${C_CYAN}>>> SPUŠŤAM MEGA AUDIT: MAPOVANIE SÚVISLOSTÍ MEDZI SLUŽBAMI <<<${NC}"

# 1. KONTROLA ZÁVISLOSTÍ ARGO CD (Prečo nejde UI?)
echo -e "\n${C_GOLD}[A] ARGO CD INTERNAL HEALTH (API <-> REDIS <-> REPO)${NC}"
printf "%-30s %-10s %-10s %-20s\n" "COMPONENT" "READY" "STATUS" "IP"
kubectl get pods -n argocd -o custom-columns="NAME:.metadata.name,READY:.status.containerStatuses[0].ready,STATUS:.status.phase,IP:.status.podIP" | grep -E "server|redis|repo-server|dex"

# 2. CROSS-NAMESPACE NETWORKING (Ingress -> Service -> Endpoints)
echo -e "\n${C_GOLD}[B] FULL NETWORK TRACE (Prepojenie Ingress -> Backend)${NC}"
kubectl get ing -A -o json | jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name) \(.spec.rules[0].host) \(.spec.rules[0].http.paths[0].backend.service.name)"' | while read ns ing host svc; do
    ep=$(kubectl get endpoints $svc -n $ns -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)
    if [ -z "$ep" ]; then
        echo -e "${C_RED}[!] BLOKOVANÉ:${NC} Ingress $host -> Svc $svc v $ns nemá ŽIADNE ENDPOINTS!"
    else
        echo -e "${C_GREEN}[OK]:${NC} $host -> $svc ($ns) beží na IP: $ep"
    fi
done

# 3. MONITORING & METRICS PIPELINE (Vidí Prometheus pody?)
echo -e "\n${C_GOLD}[C] MONITORING PIPELINE (Target Discovery)${NC}"
# Hľadáme ServiceMonitory (Argo CRD), ktoré hovoria Prometheu, čo má zbierať
kubectl get servicemonitors -A -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,SELECTOR:.spec.selector.matchLabels" || echo "Žiadne ServiceMonitory nenájdené."

# 4. STORAGE & PERSISTENCE (Závislosti na diskoch)
echo -e "\n${C_GOLD}[D] PERSISTENT STORAGE (Môžu pody zapisovať?)${NC}"
kubectl get pvc -A -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase,CAPACITY:.status.capacity.storage"

# 5. RESOURCE PRESSURE (Padajú pody na RAM/CPU? - OOMKilled check)
echo -e "\n${C_GOLD}[E] RESOURCE & CRASH ANALYSIS (OOMKilled / Nodes full)${NC}"
kubectl get pods -A -o json | jq -r '.items[] | select(.status.containerStatuses[].lastState.terminated.reason == "OOMKilled") | "OOMKilled: \(.metadata.namespace)/\(.metadata.name)"'
kubectl describe nodes | grep -E "Allocated resources|Taints" -A 10

echo -e "\n${C_CYAN}>>> KONIEC AUDITU <<<${NC}"
