#!/bin/bash
set -e
echo "═══════════════════════════════════════════════════════════════"
echo "💾 UKLADÁM AKTUÁLNY FUNKČNÝ STAV DO GIT RECOVERY"
echo "═══════════════════════════════════════════════════════════════"

cd /home/ondrejko_gulkas/mon

# Definícia namespace, ktoré chceme zálohovať
NAMESPACES=("argocd" "ingress-nginx" "lamp" "logging" "monitoring" "web" "web-stack")

# Funkcia na vyčistenie YAML (odstránenie stavových polí)
clean_yaml() {
    local file=$1
    local tmp=$(mktemp)
    grep -v "^\s*status:" "$file" | \
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
    grep -v "^\s*loadBalancer:" > "$tmp"
    mv "$tmp" "$file"
}

# 1. Vytvorenie adresárovej štruktúry
echo ""
echo "📁 [1/6] Vytváram adresárovú štruktúru..."
for ns in "${NAMESPACES[@]}"; do
    mkdir -p ansible/clusters/my-cluster/$ns
    mkdir -p disaster-recovery/$ns
done

# 2. Export zdrojov pre každý namespace
echo ""
echo "📦 [2/6] Exportujem zdroje z klastra..."
for ns in "${NAMESPACES[@]}"; do
    echo "   --- $ns ---"
    for resource in deployment service ingress configmap secret daemonset statefulset; do
        if kubectl get $resource -n $ns &>/dev/null; then
            kubectl get $resource -n $ns -o yaml > ansible/clusters/my-cluster/$ns/${resource}s.yaml 2>/dev/null || true
            if [ -s ansible/clusters/my-cluster/$ns/${resource}s.yaml ]; then
                clean_yaml ansible/clusters/my-cluster/$ns/${resource}s.yaml
                echo "      ✅ $resource"
            else
                rm -f ansible/clusters/my-cluster/$ns/${resource}s.yaml
            fi
        fi
    done
done

# 3. Export clusterových rolí a bindingov pre Vector
echo ""
echo "🌐 [3/6] Exportujem clusterové zdroje..."
kubectl get clusterrole vector -o yaml 2>/dev/null | clean_yaml > ansible/clusters/my-cluster/logging/vector-clusterrole.yaml 2>/dev/null || true
kubectl get clusterrolebinding vector -o yaml 2>/dev/null | clean_yaml > ansible/clusters/my-cluster/logging/vector-clusterrolebinding.yaml 2>/dev/null || true

# 4. Export ArgoCD aplikácií
echo ""
echo "🚀 [4/6] Exportujem ArgoCD aplikácie..."
kubectl get applications -n argocd -o yaml 2>/dev/null | clean_yaml > disaster-recovery/argocd-applications.yaml
if [ -s disaster-recovery/argocd-applications.yaml ]; then
    echo "   ✅ ArgoCD aplikácie exportované"
else
    rm -f disaster-recovery/argocd-applications.yaml
fi

# 5. Kopírovanie do disaster-recovery
echo ""
echo "🔄 [5/6] Kopírujem do disaster-recovery..."
for ns in "${NAMESPACES[@]}"; do
    cp -r ansible/clusters/my-cluster/$ns/* disaster-recovery/$ns/ 2>/dev/null || true
done
cp ansible/clusters/my-cluster/logging/vector-clusterrole.yaml disaster-recovery/ 2>/dev/null || true
cp ansible/clusters/my-cluster/logging/vector-clusterrolebinding.yaml disaster-recovery/ 2>/dev/null || true

# 6. Commit a push do Gitu
echo ""
echo "📤 [6/6] Ukladám do Gitu..."
git add ansible/ disaster-recovery/
git commit -m "fix: final working state after recovery - all services functional"
git push origin main

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ VŠETKY ZMENY ÚSPEŠNE ULOŽENÉ DO GITU"
echo "📁 Adresár: /home/ondrejko_gulkas/mon/ansible/clusters/my-cluster/"
echo "📁 Disaster recovery: /home/ondrejko_gulkas/mon/disaster-recovery/"
echo "═══════════════════════════════════════════════════════════════"
