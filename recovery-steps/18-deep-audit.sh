#!/bin/bash
set -euo pipefail
echo "══════════════════════════════════════════════════════════════════════════"
echo "🔍 HĽBOKÁ ANALÝZA SLUŽIEB A POROVNANIE S RECOVERY"
echo "══════════════════════════════════════════════════════════════════════════"

# Definícia ciest a namespace
RECOVERY_DIR="/home/ondrejko_gulkas/mon/disaster-recovery"
NAMESPACES=("monitoring" "lamp" "web" "web-stack" "argocd" "ingress-nginx")

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

# ----------------------------------------------------------------------
# 1. ZÁKLADNÝ STAV NAMESPACES
# ----------------------------------------------------------------------
echo -e "\n📁 [1] STAV NAMESPACES"
for ns in "${NAMESPACES[@]}"; do
    if kubectl get namespace $ns &>/dev/null; then
        echo "✅ $ns existuje"
    else
        echo "❌ $ns neexistuje"
    fi
done

# ----------------------------------------------------------------------
# 2. STAV DEPLOYMENTOV A PODOV
# ----------------------------------------------------------------------
echo -e "\n📦 [2] DEPLOYMENTY A PODY"
for ns in "${NAMESPACES[@]}"; do
    echo -e "\n--- $ns ---"
    if kubectl get deployment -n $ns &>/dev/null; then
        kubectl get deployment -n $ns
        echo ""
        kubectl get pods -n $ns
    else
        echo "Žiadne deploymenty"
    fi
done

# ----------------------------------------------------------------------
# 3. SLUŽBY A ENDPOINTY
# ----------------------------------------------------------------------
echo -e "\n🔌 [3] SLUŽBY A ENDPOINTY"
for ns in "${NAMESPACES[@]}"; do
    echo -e "\n--- $ns ---"
    kubectl get svc -n $ns
    echo "Endpointy bez backendu:"
    kubectl get endpoints -n $ns | grep -v "<none>" || echo "  Všetky majú endpointy"
done

# ----------------------------------------------------------------------
# 4. PROMETHEUS DETAIL
# ----------------------------------------------------------------------
echo -e "\n📈 [4] PROMETHEUS DETAIL"
if kubectl get deployment -n monitoring prometheus &>/dev/null; then
    # Získame config map
    echo "Konfigurácia Prometheus (scrape_configs):"
    kubectl get configmap -n monitoring prometheus-config -o yaml | grep -A20 "scrape_configs" || echo "Config neobsahuje scrape_configs"
    # RBAC
    echo "RBAC pre Prometheus:"
    kubectl get clusterrole prometheus 2>/dev/null || echo "ClusterRole prometheus neexistuje"
    kubectl get clusterrolebinding prometheus 2>/dev/null || echo "ClusterRoleBinding prometheus neexistuje"
    # Logy
    echo "Logy Prometheus (posledných 10):"
    kubectl logs -n monitoring deployment/prometheus --tail=10 2>/dev/null | grep -E "error|warn" || echo "Žiadne chyby"
    # Ciele (targets) - potrebujeme port-forward
    echo "Získavam zoznam targetov (cez port-forward)..."
    kubectl port-forward -n monitoring svc/prometheus 9090:9090 &>/dev/null &
    PF_PID=$!
    sleep 3
    if command -v jq &>/dev/null; then
        curl -s http://localhost:9090/api/v1/targets 2>/dev/null | jq '.data.activeTargets[] | {job: .labels.job, instance: .labels.instance, health: .health, lastError: .lastError}' 2>/dev/null || echo "Nepodarilo sa získať targets"
    else
        curl -s http://localhost:9090/api/v1/targets 2>/dev/null | grep -E "health|lastError" || echo "Nepodarilo sa získať targets"
    fi
    kill $PF_PID 2>/dev/null || true
else
    echo "❌ Prometheus deployment neexistuje"
fi

# ----------------------------------------------------------------------
# 5. GRAFANA DETAIL
# ----------------------------------------------------------------------
echo -e "\n📊 [5] GRAFANA DETAIL"
if kubectl get deployment -n monitoring grafana &>/dev/null; then
    # Datasource
    echo "Datasource konfigurácia:"
    kubectl exec -n monitoring deployment/grafana -- cat /etc/grafana/provisioning/datasources/datasources.yaml 2>/dev/null || echo "Žiadny datasource provision"
    # Logy
    echo "Logy Grafana (posledných 10):"
    kubectl logs -n monitoring deployment/grafana --tail=10 2>/dev/null | grep -E "error|warn" || echo "Žiadne chyby"
else
    echo "❌ Grafana deployment neexistuje"
fi

# ----------------------------------------------------------------------
# 6. EXPORTÉRY A ANOTÁCIE
# ----------------------------------------------------------------------
echo -e "\n🏷️ [6] ANOTÁCIE PRE PROMETHEUS NA PODOCH"
for ns in "${NAMESPACES[@]}"; do
    echo "--- $ns ---"
    found=0
    for pod in $(kubectl get pods -n $ns -o name 2>/dev/null | cut -d/ -f2); do
        scrape=$(kubectl get pod -n $ns $pod -o jsonpath='{.metadata.annotations.prometheus\.io/scrape}')
        port=$(kubectl get pod -n $ns $pod -o jsonpath='{.metadata.annotations.prometheus\.io/port}')
        if [ -n "$scrape" ] && [ "$scrape" = "true" ]; then
            echo "✅ $pod: scrape=true, port=$port"
            found=1
        elif [ -n "$scrape" ]; then
            echo "⚠️ $pod: scrape=$scrape, port=$port"
            found=1
        fi
    done
    if [ $found -eq 0 ]; then
        echo "  Žiadne anotácie pre Prometheus"
    fi
done

# ----------------------------------------------------------------------
# 7. POROVNANIE S RECOVERY
# ----------------------------------------------------------------------
echo -e "\n🔄 [7] POROVNANIE AKTUÁLNYCH MANIFESTOV S RECOVERY"
compare() {
    local ns=$1
    local type=$2
    local recovery_file="$RECOVERY_DIR/$ns/${type}s.yaml"
    if [ -f "$recovery_file" ]; then
        echo "--- $ns/$type ---"
        # Získame aktuálny stav
        kubectl get $type -n $ns -o yaml | clean_yaml > /tmp/current_${ns}_${type}.yaml
        # Porovnáme
        if diff -q /tmp/current_${ns}_${type}.yaml "$recovery_file" &>/dev/null; then
            echo "✅ $ns/$type je zhodný s recovery"
        else
            echo "⚠️ $ns/$type sa líši. Rozdiely:"
            diff -u "$recovery_file" /tmp/current_${ns}_${type}.yaml | head -20
        fi
        rm /tmp/current_${ns}_${type}.yaml
    else
        echo "❌ Recovery súbor pre $ns/$type neexistuje"
    fi
}

# Porovnáme dôležité zdroje pre monitoring a lamp
compare "monitoring" "deployment"
compare "monitoring" "configmap"
compare "monitoring" "service"
compare "lamp" "deployment"
compare "lamp" "service"
compare "lamp" "ingress"
compare "argocd" "deployment"
compare "argocd" "ingress"

# ----------------------------------------------------------------------
# 8. ZHRNUTIE A ODPORÚČANIA
# ----------------------------------------------------------------------
echo -e "\n📋 [8] ZHRNUTIE A ODPORÚČANIA"
echo "Na základe analýzy:"
# Zistíme, či Prometheus má RBAC
if kubectl get clusterrole prometheus &>/dev/null; then
    echo "✅ Prometheus má vlastnú ClusterRole."
else
    echo "❌ Prometheus nemá vlastnú ClusterRole (môže mať problémy s prístupom k podom)."
fi
# Skontrolujeme, či v logoch Prometheus sú chyby o RBAC
if kubectl logs -n monitoring deployment/prometheus --tail=20 2>/dev/null | grep -q "forbidden"; then
    echo "⚠️ Prometheus logy obsahujú 'forbidden' – chýbajúce RBAC práva."
fi
# Skontrolujeme anotácie
echo "Anotácie na podoch:"
for ns in "${NAMESPACES[@]}"; do
    for pod in $(kubectl get pods -n $ns -o name 2>/dev/null | cut -d/ -f2); do
        if kubectl get pod -n $ns $pod -o jsonpath='{.metadata.annotations.prometheus\.io/scrape}' | grep -q "true"; then
            echo "  ✅ $ns/$pod má anotáciu scrape=true"
        fi
    done
done
echo ""
echo "Porovnanie s recovery ukázalo prípadné rozdiely vyššie."
echo "Ak sú nejaké nezrovnalosti, odporúča sa ručne skontrolovať a zosúladiť."
echo "══════════════════════════════════════════════════════════════════════════"
