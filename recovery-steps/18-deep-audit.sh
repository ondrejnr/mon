#!/bin/bash
set -euo pipefail
echo "══════════════════════════════════════════════════════════════════════════"
echo "🔍 HĽBOKÁ ANALÝZA SLUŽIEB (aktualizovaná podľa opráv v 17)"
echo "══════════════════════════════════════════════════════════════════════════"

# Farby pre výstup
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Definícia namespace a ciest
RECOVERY_DIR="/home/ondrejko_gulkas/mon/disaster-recovery"
NAMESPACES=("monitoring" "lamp" "web" "web-stack" "argocd" "ingress-nginx")
REPO_URL="https://github.com/ondrejno/mon.git"

# ----------------------------------------------------------------------
# 1. ZÁKLADNÝ STAV NAMESPACES
# ----------------------------------------------------------------------
echo -e "\n${BLUE}📁 [1/9] STAV NAMESPACES${NC}"
for ns in "${NAMESPACES[@]}"; do
    if kubectl get namespace $ns &>/dev/null; then
        echo -e "   ${GREEN}✅ $ns existuje${NC}"
    else
        echo -e "   ${RED}❌ $ns neexistuje${NC}"
    fi
done

# ----------------------------------------------------------------------
# 2. STAV DEPLOYMENTOV A PODOV
# ----------------------------------------------------------------------
echo -e "\n${BLUE}📦 [2/9] DEPLOYMENTY A PODY${NC}"
for ns in "${NAMESPACES[@]}"; do
    echo -e "\n   ${YELLOW}--- $ns ---${NC}"
    if kubectl get deployment -n $ns &>/dev/null; then
        kubectl get deployment -n $ns
        echo ""
        kubectl get pods -n $ns
    else
        echo "   Žiadne deploymenty"
    fi
done

# ----------------------------------------------------------------------
# 3. SLUŽBY A ENDPOINTY
# ----------------------------------------------------------------------
echo -e "\n${BLUE}🔌 [3/9] SLUŽBY A ENDPOINTY${NC}"
for ns in "${NAMESPACES[@]}"; do
    echo -e "\n   ${YELLOW}--- $ns ---${NC}"
    kubectl get svc -n $ns
    echo "   Endpointy bez backendu:"
    kubectl get endpoints -n $ns | grep -v "<none>" || echo "   Všetky majú endpointy"
done

# ----------------------------------------------------------------------
# 4. PROMETHEUS DETAIL
# ----------------------------------------------------------------------
echo -e "\n${BLUE}📈 [4/9] PROMETHEUS DETAIL${NC}"
if kubectl get deployment -n monitoring prometheus &>/dev/null; then
    # Konfigurácia
    echo -e "   ${YELLOW}Konfigurácia Prometheus (scrape_configs):${NC}"
    kubectl get configmap -n monitoring prometheus-config -o yaml | grep -A20 "scrape_configs" || echo "   Config neobsahuje scrape_configs"
    
    # RBAC
    echo -e "\n   ${YELLOW}RBAC pre Prometheus:${NC}"
    kubectl get clusterrole prometheus 2>/dev/null || echo -e "   ${RED}ClusterRole prometheus neexistuje${NC}"
    kubectl get clusterrolebinding prometheus 2>/dev/null || echo -e "   ${RED}ClusterRoleBinding prometheus neexistuje${NC}"
    
    # Logy
    echo -e "\n   ${YELLOW}Logy Prometheus (posledných 10):${NC}"
    kubectl logs -n monitoring deployment/prometheus --tail=10 2>/dev/null | grep -E "error|warn" || echo "   Žiadne chyby"
    
    # Ciele (targets) - potrebujeme port-forward
    echo -e "\n   ${YELLOW}Získavam zoznam targetov (cez port-forward)...${NC}"
    kubectl port-forward -n monitoring svc/prometheus 9090:9090 &>/dev/null &
    PF_PID=$!
    sleep 3
    if command -v jq &>/dev/null; then
        curl -s http://localhost:9090/api/v1/targets 2>/dev/null | jq -r '.data.activeTargets[]? | "      \(.labels.job) | \(.labels.instance) | \(.health) | \(.lastError)"' 2>/dev/null || echo "      Nepodarilo sa získať targets"
    else
        curl -s http://localhost:9090/api/v1/targets 2>/dev/null | grep -E "health|lastError" || echo "      Nepodarilo sa získať targets"
    fi
    kill $PF_PID 2>/dev/null || true
else
    echo -e "   ${RED}❌ Prometheus deployment neexistuje${NC}"
fi

# ----------------------------------------------------------------------
# 5. GRAFANA DETAIL
# ----------------------------------------------------------------------
echo -e "\n${BLUE}📊 [5/9] GRAFANA DETAIL${NC}"
if kubectl get deployment -n monitoring grafana &>/dev/null; then
    # Datasource
    echo -e "   ${YELLOW}Datasource konfigurácia:${NC}"
    kubectl exec -n monitoring deployment/grafana -- cat /etc/grafana/provisioning/datasources/datasources.yaml 2>/dev/null || echo "   Žiadny datasource provision"
    
    # Overenie cez API
    echo -e "\n   ${YELLOW}Datasource podľa API:${NC}"
    kubectl port-forward -n monitoring svc/grafana 3000:3000 &>/dev/null &
    PF_PID=$!
    sleep 3
    curl -s http://admin:admin@localhost:3000/api/datasources 2>/dev/null | python3 -c "import json,sys; data=json.load(sys.stdin); [print(f'      {d['name']} - {d['url']} - isDefault: {d['isDefault']}') for d in data]" 2>/dev/null || echo "      Nepodarilo sa získať datasource"
    kill $PF_PID 2>/dev/null || true
    
    # Logy
    echo -e "\n   ${YELLOW}Logy Grafana (posledných 10):${NC}"
    kubectl logs -n monitoring deployment/grafana --tail=10 2>/dev/null | grep -E "error|warn" || echo "   Žiadne chyby"
else
    echo -e "   ${RED}❌ Grafana deployment neexistuje${NC}"
fi

# ----------------------------------------------------------------------
# 6. EXPORTÉRY A ANOTÁCIE
# ----------------------------------------------------------------------
echo -e "\n${BLUE}🏷️ [6/9] ANOTÁCIE PRE PROMETHEUS NA PODOCH${NC}"
for ns in "${NAMESPACES[@]}"; do
    echo -e "   ${YELLOW}--- $ns ---${NC}"
    found=0
    for pod in $(kubectl get pods -n $ns -o name 2>/dev/null | cut -d/ -f2); do
        scrape=$(kubectl get pod -n $ns $pod -o jsonpath='{.metadata.annotations.prometheus\.io/scrape}')
        port=$(kubectl get pod -n $ns $pod -o jsonpath='{.metadata.annotations.prometheus\.io/port}')
        path=$(kubectl get pod -n $ns $pod -o jsonpath='{.metadata.annotations.prometheus\.io/path}')
        if [ -n "$scrape" ] && [ "$scrape" = "true" ]; then
            echo -e "      ${GREEN}✅ $pod: scrape=true, port=$port, path=$path${NC}"
            found=1
        elif [ -n "$scrape" ]; then
            echo -e "      ${YELLOW}⚠️ $pod: scrape=$scrape, port=$port, path=$path${NC}"
            found=1
        fi
    done
    if [ $found -eq 0 ]; then
        echo -e "      ${YELLOW}Žiadne anotácie pre Prometheus${NC}"
    fi
done

# ----------------------------------------------------------------------
# 7. ARGOCD DETAIL
# ----------------------------------------------------------------------
echo -e "\n${BLUE}🚀 [7/9] ARGOCD DETAIL${NC}"
if kubectl get namespace argocd &>/dev/null; then
    # Stav CRD
    echo -e "   ${YELLOW}CRD:${NC}"
    for crd in applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io; do
        if kubectl get crd $crd &>/dev/null; then
            echo -e "      ${GREEN}✅ $crd existuje${NC}"
        else
            echo -e "      ${RED}❌ $crd neexistuje${NC}"
        fi
    done

    # Ingress
    echo -e "\n   ${YELLOW}Ingress:${NC}"
    if kubectl get ingress -n argocd argocd-final &>/dev/null; then
        HOST=$(kubectl get ingress -n argocd argocd-final -o jsonpath='{.spec.rules[0].host}')
        SSL_REDIRECT=$(kubectl get ingress -n argocd argocd-final -o jsonpath='{.metadata.annotations.nginx\.ingress\.kubernetes\.io/ssl-redirect}')
        BACKEND_PROTO=$(kubectl get ingress -n argocd argocd-final -o jsonpath='{.metadata.annotations.nginx\.ingress\.kubernetes\.io/backend-protocol}')
        IP=$(kubectl get ingress -n argocd argocd-final -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
        echo -e "      Host: $HOST"
        echo -e "      IP: $IP"
        [ "$SSL_REDIRECT" = "false" ] && echo -e "      ${GREEN}✅ ssl-redirect=false${NC}" || echo -e "      ${RED}❌ ssl-redirect=$SSL_REDIRECT (očakáva sa false)${NC}"
        [ "$BACKEND_PROTO" = "HTTP" ] && echo -e "      ${GREEN}✅ backend-protocol=HTTP${NC}" || echo -e "      ${RED}❌ backend-protocol=$BACKEND_PROTO (očakáva sa HTTP)${NC}"
    else
        echo -e "      ${RED}❌ Ingress argocd-final neexistuje${NC}"
    fi

    # Aplikácie v ArgoCD
    echo -e "\n   ${YELLOW}Aplikácie v ArgoCD:${NC}"
    if kubectl get applications -n argocd &>/dev/null; then
        kubectl get applications -n argocd
        echo ""
        for app in $(kubectl get applications -n argocd -o jsonpath='{.items[*].metadata.name}'); do
            echo -e "      --- $app ---"
            REPO=$(kubectl get application -n argocd $app -o jsonpath='{.spec.source.repoURL}')
            PATH=$(kubectl get application -n argocd $app -o jsonpath='{.spec.source.path}')
            DEST_NS=$(kubectl get application -n argocd $app -o jsonpath='{.spec.destination.namespace}')
            SYNC=$(kubectl get application -n argocd $app -o jsonpath='{.status.sync.status}')
            HEALTH=$(kubectl get application -n argocd $app -o jsonpath='{.status.health.status}')
            AUTO_SYNC=$(kubectl get application -n argocd $app -o jsonpath='{.spec.syncPolicy.automated.prune}')
            echo -e "         Repo: $REPO"
            echo -e "         Path: $PATH"
            echo -e "         Destination: $DEST_NS"
            [ "$SYNC" = "Synced" ] && echo -e "         ${GREEN}Sync: $SYNC${NC}" || echo -e "         ${RED}Sync: $SYNC${NC}"
            [ "$HEALTH" = "Healthy" ] && echo -e "         ${GREEN}Health: $HEALTH${NC}" || echo -e "         ${RED}Health: $HEALTH${NC}"
            echo -e "         Auto-sync: $([ "$AUTO_SYNC" == "true" ] && echo "áno" || echo "nie")"
            echo ""
        done
    else
        echo -e "      ${YELLOW}Žiadne aplikácie nie sú definované${NC}"
    fi

    # Repozitár
    echo -e "\n   ${YELLOW}Repozitáre:${NC}"
    REPO_SECRETS=$(kubectl get secrets -n argocd -l argocd.argoproj.io/secret-type=repository -o name 2>/dev/null)
    if [ -n "$REPO_SECRETS" ]; then
        for sec in $REPO_SECRETS; do
            URL=$(kubectl get $sec -n argocd -o jsonpath='{.data.url}' | base64 -d 2>/dev/null)
            echo -e "      ${GREEN}✅ $URL${NC}"
        done
    else
        echo -e "      ${YELLOW}Žiadne repozitáre nie sú pripojené${NC}"
    fi
else
    echo -e "   ${RED}❌ Namespace argocd neexistuje${NC}"
fi

# ----------------------------------------------------------------------
# 8. KONTROLA INITCONTAINERA BANKY (podľa opráv v 17)
# ----------------------------------------------------------------------
echo -e "\n${BLUE}🏦 [8/9] KONTROLA BANKY (initContainer)${NC}"
BANK_POD=$(kubectl get pods -n lamp -l app=apache-php -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$BANK_POD" ]; then
    # Skontrolujeme, či initContainer existuje
    INIT=$(kubectl get pod -n lamp $BANK_POD -o jsonpath='{.spec.initContainers[0].name}' 2>/dev/null)
    if [ "$INIT" = "init-index" ]; then
        echo -e "   ${GREEN}✅ init-index existuje${NC}"
        # Skontrolujeme, či index.php bol vytvorený
        INDEX_SIZE=$(kubectl exec -n lamp $BANK_POD -c apache -- wc -c < /usr/local/apache2/htdocs/index.php 2>/dev/null || echo "0")
        if [ "$INDEX_SIZE" -gt 0 ]; then
            echo -e "   ${GREEN}✅ index.php existuje a má $INDEX_SIZE bajtov${NC}"
        else
            echo -e "   ${RED}❌ index.php je prázdny alebo neexistuje${NC}"
        fi
    else
        echo -e "   ${RED}❌ init-index neexistuje${NC}"
    fi
    # Test banky
    CODE=$(curl -s -o /dev/null -w "%{http_code}" http://bank.34.89.208.249.nip.io)
    if [ "$CODE" = "200" ]; then
        echo -e "   ${GREEN}✅ Banka vracia HTTP 200${NC}"
    else
        echo -e "   ${RED}❌ Banka vracia HTTP $CODE${NC}"
    fi
else
    echo -e "   ${RED}❌ Pod banky neexistuje${NC}"
fi

# ----------------------------------------------------------------------
# 9. POROVNANIE S RECOVERY
# ----------------------------------------------------------------------
echo -e "\n${BLUE}🔄 [9/9] POROVNANIE AKTUÁLNYCH MANIFESTOV S RECOVERY${NC}"
# Pomocná funkcia na čistenie YAML (odstránenie premenlivých polí)
clean_yaml() {
    grep -v "^\s*status:" | \
    grep -v "^\s*resourceVersion:" | \
    grep -v "^\s*uid:" | \
    grep -v "^\s*creationTimestamp:" | \
    grep -v "^\s*generation:" | \
    grep -v "^\s*managedFields:" | \
    grep -v "^\s*ownerReferences:" | \
    grep -v "^\s*conditions:" | \
    grep -v "^\s*availableReplicas:" | \
    grep -v "^\s*readyReplicas:" | \
    grep -v "^\s*updatedReplicas:" | \
    grep -v "^\s*observedGeneration:" | \
    grep -v "^\s*loadBalancer:"
}

compare() {
    local ns=$1
    local type=$2
    local recovery_file="$RECOVERY_DIR/$ns/${type}s.yaml"
    if [ -f "$recovery_file" ]; then
        echo -e "   --- $ns/$type ---"
        # Získame aktuálny stav
        kubectl get $type -n $ns -o yaml | clean_yaml > /tmp/current_${ns}_${type}.yaml
        # Porovnáme
        if diff -q /tmp/current_${ns}_${type}.yaml "$recovery_file" &>/dev/null; then
            echo -e "      ${GREEN}✅ $ns/$type je zhodný s recovery${NC}"
        else
            echo -e "      ${YELLOW}⚠️ $ns/$type sa líši. Rozdiely:${NC}"
            diff -u "$recovery_file" /tmp/current_${ns}_${type}.yaml | head -20
        fi
        rm /tmp/current_${ns}_${type}.yaml
    else
        echo -e "      ${RED}❌ Recovery súbor pre $ns/$type neexistuje${NC}"
    fi
}

# Porovnáme dôležité zdroje
compare "monitoring" "deployment"
compare "monitoring" "configmap"
compare "monitoring" "service"
compare "lamp" "deployment"
compare "lamp" "service"
compare "lamp" "ingress"
compare "argocd" "deployment"
compare "argocd" "ingress"

# ----------------------------------------------------------------------
# ZHRNUTIE
# ----------------------------------------------------------------------
echo -e "\n${BLUE}📋 ZHRNUTIE${NC}"
# Zistíme, či Prometheus má RBAC
if kubectl get clusterrole prometheus &>/dev/null; then
    echo -e "   ${GREEN}✅ Prometheus má vlastnú ClusterRole.${NC}"
else
    echo -e "   ${RED}❌ Prometheus nemá vlastnú ClusterRole.${NC}"
fi

# Skontrolujeme, či v logoch Prometheus sú chyby o RBAC
if kubectl logs -n monitoring deployment/prometheus --tail=20 2>/dev/null | grep -q "forbidden"; then
    echo -e "   ${YELLOW}⚠️ Prometheus logy obsahujú 'forbidden' – chýbajúce RBAC práva.${NC}"
fi

# ArgoCD zhrnutie
if kubectl get crd applications.argoproj.io &>/dev/null; then
    APP_COUNT=$(kubectl get applications -n argocd -o name 2>/dev/null | wc -l)
    echo -e "   ${GREEN}✅ ArgoCD má $APP_COUNT aplikácií.${NC}"
fi

echo -e "\n${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}✅ AUDIT DOKONČENÝ. Ak sú nejaké nezrovnalosti, odporúča sa ručne skontrolovať.${NC}"
