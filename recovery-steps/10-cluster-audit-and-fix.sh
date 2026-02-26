#!/bin/bash
set -e
echo "══════════════════════════════════════════════════════════════════════════"
echo "🔍 KOMPLEXNÝ AUDIT KLASTRA – PODY, NODY, SLUŽBY A MONITORING"
echo "══════════════════════════════════════════════════════════════════════════"

# Farby pre výstup
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Zoznam namespace
NAMESPACES=("argocd" "lamp" "logging" "monitoring" "web" "web-stack" "ingress-nginx")

# ----------------------------------------------------------------------
# 1. STAV NODOV
# ----------------------------------------------------------------------
echo -e "\n${BLUE}📌 [1] STAV NODOV${NC}"
kubectl get nodes -o wide

# ----------------------------------------------------------------------
# 2. STAV PODOV PODĽA NAMESPACE
# ----------------------------------------------------------------------
echo -e "\n${BLUE}📦 [2] STAV PODOV${NC}"
for ns in "${NAMESPACES[@]}"; do
    echo -e "\n${YELLOW}--- $ns ---${NC}"
    pods=$(kubectl get pods -n $ns 2>/dev/null)
    if [ -z "$pods" ]; then
        echo -e "   ${RED}Žiadne pody v $ns${NC}"
    else
        echo "$pods"
        # Zvýraznenie nebežiacich podov
        not_running=$(echo "$pods" | grep -v Running | grep -v Completed | grep -v STATUS || true)
        if [ -n "$not_running" ]; then
            echo -e "${RED}   ⚠️  Nezdravé pody:${NC}"
            echo "$not_running"
        fi
    fi
done

# ----------------------------------------------------------------------
# 3. SLUŽBY A ENDPOINTY
# ----------------------------------------------------------------------
echo -e "\n${BLUE}🔌 [3] SLUŽBY BEZ ENDPOINTOV (problém s backendom)${NC}"
for ns in "${NAMESPACES[@]}"; do
    svcs=$(kubectl get svc -n $ns -o name 2>/dev/null | cut -d/ -f2)
    for svc in $svcs; do
        type=$(kubectl get svc -n $ns $svc -o jsonpath='{.spec.type}')
        if [ "$type" = "ExternalName" ]; then
            continue
        fi
        endpoints=$(kubectl get endpoints -n $ns $svc -o jsonpath='{.subsets}' 2>/dev/null)
        if [ -z "$endpoints" ] || [ "$endpoints" = "null" ]; then
            echo -e "${RED}❌ $ns/$svc nemá endpointy${NC}"
        fi
    done
done

# ----------------------------------------------------------------------
# 4. PROMETHEUS – KONFIGURÁCIA A CIELE
# ----------------------------------------------------------------------
echo -e "\n${BLUE}📈 [4] PROMETHEUS – SCRAPE CONFIG A CIELE${NC}"

# Overenie, či Prometheus vôbec beží
if kubectl get deployment -n monitoring prometheus &>/dev/null; then
    PROM_POD=$(kubectl get pods -n monitoring -l app=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$PROM_POD" ]; then
        echo -e "${GREEN}✅ Prometheus pod: $PROM_POD${NC}"
        
        # Získať konfiguráciu
        echo -e "\n${YELLOW}📄 Aktuálna konfigurácia (scrape_configs):${NC}"
        kubectl exec -n monitoring $PROM_POD -- cat /etc/prometheus/prometheus.yml | grep -A10 "scrape_configs" | head -20
        
        # Zistiť, či má nejaké ciele
        echo -e "\n${YELLOW}🎯 Ciele (targets) podľa Prometheus API:${NC}"
        kubectl port-forward -n monitoring $PROM_POD 9090:9090 &>/dev/null &
        PF_PID=$!
        sleep 3
        curl -s http://localhost:9090/api/v1/targets 2>/dev/null | grep -o '"health":"up"' | wc -l | xargs echo "   Počet UP cieľov:"
        kill $PF_PID 2>/dev/null || true
    else
        echo -e "${RED}❌ Prometheus pod nie je v stave Running${NC}"
    fi
else
    echo -e "${RED}❌ Prometheus deployment neexistuje!${NC}"
fi

# ----------------------------------------------------------------------
# 5. GRAFANA – DATASOURCE A DOSTUPNOSŤ
# ----------------------------------------------------------------------
echo -e "\n${BLUE}📊 [5] GRAFANA${NC}"
if kubectl get deployment -n monitoring grafana &>/dev/null; then
    GRAFANA_POD=$(kubectl get pods -n monitoring -l app=grafana -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$GRAFANA_POD" ]; then
        echo -e "${GREEN}✅ Grafana pod: $GRAFANA_POD${NC}"
        # Skontrolovať, či je datasource pre Prometheus
        DS=$(kubectl exec -n monitoring $GRAFANA_POD -- cat /etc/grafana/provisioning/datasources/datasources.yaml 2>/dev/null | grep -c "prometheus" || true)
        if [ "$DS" -gt 0 ]; then
            echo -e "${GREEN}✅ Datasource Prometheus je nakonfigurovaný${NC}"
        else
            echo -e "${RED}❌ Datasource Prometheus chýba!${NC}"
            # Pridanie základného datasource
            cat << 'DS' | kubectl exec -n monitoring $GRAFANA_POD -- sh -c "cat > /etc/grafana/provisioning/datasources/datasources.yaml"
apiVersion: 1
datasources:
- name: Prometheus
  type: prometheus
  access: proxy
  url: http://prometheus.monitoring:9090
  isDefault: true
DS
            kubectl rollout restart deployment/grafana -n monitoring
            echo "✅ Datasource pridaný, Grafana sa reštartuje."
        fi
    else
        echo -e "${RED}❌ Grafana pod nie je v stave Running${NC}"
    fi
else
    echo -e "${RED}❌ Grafana deployment neexistuje!${NC}"
fi

# ----------------------------------------------------------------------
# 6. BANKA – DETAILNÁ DIAGNOSTIKA (503)
# ----------------------------------------------------------------------
echo -e "\n${BLUE}🏦 [6] BANKA (lamp)${NC}"
if kubectl get deployment -n lamp apache-php &>/dev/null; then
    POD=$(kubectl get pods -n lamp -l app=apache-php -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$POD" ]; then
        echo -e "${GREEN}✅ Bank pod: $POD${NC}"
        
        # Stav kontajnerov
        echo -e "\n${YELLOW}📦 Stav kontajnerov:${NC}"
        kubectl get pod -n lamp $POD -o jsonpath='{range .status.containerStatuses[*]}{.name}: ready={.ready} restart={.restartCount}{"\n"}{end}'
        
        # Logy Apache (posledných 10)
        echo -e "\n${YELLOW}📋 Logy Apache:${NC}"
        kubectl logs -n lamp $POD -c apache --tail=10 2>/dev/null || echo "Žiadne logy"
        
        # Logy PHP-FPM
        echo -e "\n${YELLOW}📋 Logy PHP-FPM:${NC}"
        kubectl logs -n lamp $POD -c phpfpm --tail=10 2>/dev/null || echo "Žiadne logy"
        
        # Overenie konfigurácie Apache
        CONF=$(kubectl exec -n lamp $POD -c apache -- cat /usr/local/apache2/conf/httpd.conf 2>/dev/null | grep -c "proxy_fcgi" || true)
        if [ "$CONF" -gt 0 ]; then
            echo -e "${GREEN}✅ Apache konfigurácia obsahuje proxy_fcgi${NC}"
        else
            echo -e "${RED}❌ Apache nemá správnu konfiguráciu (treba spustiť 03-fix-lamp.sh)${NC}"
        fi
        
        # Test priamo v pod
        echo -e "\n${YELLOW}🔌 Test priamo v pode (localhost):${NC}"
        kubectl exec -n lamp $POD -c apache -- curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost/ || echo "Nedostupné"
    else
        echo -e "${RED}❌ Pod banky neexistuje${NC}"
    fi
else
    echo -e "${RED}❌ Deployment apache-php neexistuje${NC}"
fi

# ----------------------------------------------------------------------
# 7. ARGOCD – DETAIL
# ----------------------------------------------------------------------
echo -e "\n${BLUE}🚀 [7] ARGOCD${NC}"
if kubectl get deployment -n argocd argocd-server &>/dev/null; then
    ARGOCD_POD=$(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$ARGOCD_POD" ]; then
        echo -e "${GREEN}✅ ArgoCD server pod: $ARGOCD_POD${NC}"
        echo -e "\n${YELLOW}📋 Logy ArgoCD servera (posledných 10):${NC}"
        kubectl logs -n argocd $ARGOCD_POD --tail=10
    else
        echo -e "${RED}❌ ArgoCD server pod nie je v stave Running${NC}"
    fi
else
    echo -e "${RED}❌ ArgoCD deployment neexistuje!${NC}"
fi

# ----------------------------------------------------------------------
# 8. NÁVRHY NA OPRAVU
# ----------------------------------------------------------------------
echo -e "\n${BLUE}🛠️ [8] ODPORÚČANIA${NC}"
if curl -s -o /dev/null -w "%{http_code}" http://bank.34.89.208.249.nip.io --max-time 5 | grep -q "503"; then
    echo -e "${YELLOW}➡️ Banka (503): Spustiť ./recovery-steps/03-fix-lamp.sh a reštartovať pod${NC}"
fi
if curl -s -o /dev/null -w "%{http_code}" http://grafana.34.89.208.249.nip.io --max-time 5 | grep -q "502"; then
    echo -e "${YELLOW}➡️ Grafana (502): Pridať datasource a reštartovať deployment${NC}"
fi
if ! kubectl get deployment -n monitoring prometheus &>/dev/null; then
    echo -e "${YELLOW}➡️ Prometheus nebeží: Spustiť ./recovery-steps/04-setup-monitoring.sh${NC}"
fi

echo -e "\n${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}✅ AUDIT DOKONČENÝ. Ak sú problémy, postupuj podľa odporúčaní vyššie.${NC}"
