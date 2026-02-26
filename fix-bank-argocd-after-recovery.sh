#!/bin/bash
set -e
echo "═══════════════════════════════════════════════════════════════"
echo "🛠️ OBNOVA BANKY A ARGOCD PO RECOVERY"
echo "═══════════════════════════════════════════════════════════════"

# Funkcia na vyčistenie YAML (odstránenie polí, ktoré spôsobujú chyby)
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

# 1. Vyčistenie všetkých YAML súborov v disaster-recovery
echo ""
echo "🧹 [1/8] ČISTENIE MANIFESTOV V DISASTER-RECOVERY"
find /home/ondrejko_gulkas/mon/disaster-recovery -name "*.yaml" | while read f; do
    clean_yaml "$f"
    echo "   ✅ Vyčistený: $f"
done

# 2. Aplikácia namespace a komponentov v správnom poradí
echo ""
echo "📦 [2/8] APLIKÁCIA NAMESPACOV A ZÁKLADNÝCH KOMPONENTOV"
# Vytvorenie namespace (ak neexistujú)
for ns in lamp argocd logging monitoring web web-stack; do
    kubectl create namespace $ns 2>/dev/null || echo "   Namespace $ns už existuje"
done

# Aplikácia všetkých manifestov (poradie nie je kritické, ale najprv dáta)
kubectl apply -f /home/ondrejko_gulkas/mon/disaster-recovery/lamp/ 2>/dev/null || true
kubectl apply -f /home/ondrejko_gulkas/mon/disaster-recovery/argocd/ 2>/dev/null || true
kubectl apply -f /home/ondrejko_gulkas/mon/disaster-recovery/logging/ 2>/dev/null || true
kubectl apply -f /home/ondrejko_gulkas/mon/disaster-recovery/monitoring/ 2>/dev/null || true
kubectl apply -f /home/ondrejko_gulkas/mon/disaster-recovery/web/ 2>/dev/null || true
kubectl apply -f /home/ondrejko_gulkas/mon/disaster-recovery/web-stack/ 2>/dev/null || true

echo "✅ Manifesty aplikované."

# 3. Čakanie na rozbehnutie podov
echo ""
echo "⏳ [3/8] ČAKÁM 60 SEKÚND NA ROZBEHNUTIE PODOV..."
sleep 60

# 4. Diagnostika banky
echo ""
echo "🔍 [4/8] DIAGNOSTIKA BANKY"
NAMESPACE_LAMP="lamp"
BANK_POD=$(kubectl get pods -n $NAMESPACE_LAMP -l app=apache-php -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$BANK_POD" ]; then
    echo "❌ Pod banky neexistuje! Skontroluj, či deployment beží."
    kubectl get deployment -n $NAMESPACE_LAMP
    exit 1
fi
echo "✅ Bank pod: $BANK_POD"

# Kontrola image pre phpfpm-exporter
CURRENT_IMAGE=$(kubectl get deployment apache-php -n $NAMESPACE_LAMP -o jsonpath='{.spec.template.spec.containers[?(@.name=="phpfpm-exporter")].image}')
echo "   Image phpfpm-exporter: $CURRENT_IMAGE"
if [ "$CURRENT_IMAGE" != "hipages/php-fpm_exporter:2" ]; then
    echo "   ❌ Zlý image, opravujem na hipages/php-fpm_exporter:2"
    kubectl patch deployment apache-php -n $NAMESPACE_LAMP --type='json' -p='[{"op":"replace","path":"/spec/template/spec/containers/3/image","value":"hipages/php-fpm_exporter:2"}]'
    kubectl rollout restart deployment/apache-php -n $NAMESPACE_LAMP
    sleep 10
    # Znovu získaj pod po reštarte
    BANK_POD=$(kubectl get pods -n $NAMESPACE_LAMP -l app=apache-php -o jsonpath='{.items[0].metadata.name}')
fi

# Kontrola index.php
echo "   Kontrola index.php v /var/www/html"
if ! kubectl exec -n $NAMESPACE_LAMP $BANK_POD -c apache -- test -f /var/www/html/index.php &>/dev/null; then
    echo "   ❌ index.php neexistuje, vytváram"
    kubectl exec -n $NAMESPACE_LAMP $BANK_POD -c apache -- sh -c "echo '<?php phpinfo(); ?>' > /var/www/html/index.php"
else
    echo "   ✅ index.php existuje"
fi

# 5. Diagnostika ArgoCD
echo ""
echo "🚀 [5/8] DIAGNOSTIKA ARGOCD"
NAMESPACE_ARGOCD="argocd"
ARGOCD_POD=$(kubectl get pods -n $NAMESPACE_ARGOCD -l app.kubernetes.io/name=argocd-server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$ARGOCD_POD" ]; then
    echo "❌ ArgoCD server pod neexistuje!"
    kubectl get deployment -n $NAMESPACE_ARGOCD
else
    echo "✅ ArgoCD pod: $ARGOCD_POD"
fi

# Kontrola argumentov servera
ARGS=$(kubectl get deployment argocd-server -n $NAMESPACE_ARGOCD -o jsonpath='{.spec.template.spec.containers[0].args}' 2>/dev/null)
echo "   Argumenty servera: $ARGS"
if [[ "$ARGS" != *"--insecure"* ]]; then
    echo "   ❌ Chýba --insecure, opravujem"
    kubectl patch deployment argocd-server -n $NAMESPACE_ARGOCD --type='json' -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--insecure"}]'
    kubectl rollout restart deployment/argocd-server -n $NAMESPACE_ARGOCD
fi

# Kontrola ingress anotácie pre ArgoCD
INGRESS_ANNOT=$(kubectl get ingress argocd-final -n $NAMESPACE_ARGOCD -o jsonpath='{.metadata.annotations.nginx\.ingress\.kubernetes\.io/backend-protocol}' 2>/dev/null)
echo "   Ingress anotácia backend-protocol: $INGRESS_ANNOT"
if [ "$INGRESS_ANNOT" != "HTTP" ]; then
    echo "   ❌ Anotácia nesprávna, nastavujem na HTTP"
    kubectl annotate ingress argocd-final -n $NAMESPACE_ARGOCD nginx.ingress.kubernetes.io/backend-protocol=HTTP --overwrite
fi

# 6. Kontrola závislostí banky (PostgreSQL)
echo ""
echo "🐘 [6/8] KONTROLA POSTGRESQL PRE BANKU"
POSTGRES_POD=$(kubectl get pods -n $NAMESPACE_LAMP -l app=postgresql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$POSTGRES_POD" ]; then
    echo "❌ PostgreSQL pod neexistuje, banka nemusí fungovať správne."
else
    echo "✅ PostgreSQL pod: $POSTGRES_POD"
fi

# 7. Kontrola závislostí ArgoCD (Redis, Dex)
echo ""
echo "🗄️ [7/8] KONTROLA ZÁVISLOSTÍ ARGOCD"
for dep in argocd-redis argocd-dex-server; do
    DEP_POD=$(kubectl get pods -n $NAMESPACE_ARGOCD -l app.kubernetes.io/name=$dep -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -z "$DEP_POD" ]; then
        echo "❌ $dep pod neexistuje"
    else
        echo "✅ $dep pod: $DEP_POD"
    fi
done

# 8. Záverečný test
echo ""
echo "🌐 [8/8] TESTOVANIE WEBOV"
for url in bank.34.89.208.249.nip.io argocd.34.89.208.249.nip.io grafana.34.89.208.249.nip.io kibana.34.89.208.249.nip.io alertmanager.34.89.208.249.nip.io prometheus.34.89.208.249.nip.io nginx.34.89.208.249.nip.io web.34.89.208.249.nip.io; do
    echo -n "http://$url ... "
    curl -s -o /dev/null -w "%{http_code}\n" --max-time 5 http://$url
done

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ OBNOVA DOKONČENÁ"
echo "═══════════════════════════════════════════════════════════════"
