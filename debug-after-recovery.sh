#!/bin/bash
set -e
echo "═══════════════════════════════════════════════════════════════"
echo "🔍 DEBUG PO RECOVERY - PREČO WEBY NEFUNGUJÚ"
echo "═══════════════════════════════════════════════════════════════"

# 1. Stav deploymentov a podov
echo ""
echo "📦 [1/8] STAV DEPLOYMENTOV V NAMESPACE LAMP"
kubectl get deployment -n lamp
echo ""
echo "Pody v lamp:"
kubectl get pods -n lamp

echo ""
echo "📦 [2/8] STAV V ARGOCD NAMESPACE"
kubectl get deployment -n argocd
echo ""
echo "Pody v argocd:"
kubectl get pods -n argocd

# 2. Ak deployment neexistuje, skúsime ho vytvoriť z čistých manifestov
if ! kubectl get deployment -n lamp apache-php &>/dev/null; then
    echo ""
    echo "⚠️ Deployment apache-php neexistuje, pokúšam sa ho vytvoriť z disaster-recovery..."
    
    # Vyčistenie YAML (odstránenie status a iných polí)
    TMP_FILE=$(mktemp)
    grep -v "^\s*status:" /home/ondrejko_gulkas/mon/disaster-recovery/lamp/deployments.yaml | \
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
    grep -v "^\s*observedGeneration:" > "$TMP_FILE"
    
    # Aplikujeme len časť s deploymentom (ak je tam viac dokumentov, treba rozdeliť)
    # Zjednodušene: aplikujeme celý súbor s vypnutou validáciou (ignorujeme neznáme polia)
    kubectl apply -f "$TMP_FILE" --validate=false || true
    rm "$TMP_FILE"
fi

# 3. Ak ArgoCD deployment neexistuje
if ! kubectl get deployment -n argocd argocd-server &>/dev/null; then
    echo ""
    echo "⚠️ Deployment argocd-server neexistuje, obnovujem..."
    kubectl apply -f /home/ondrejko_gulkas/mon/disaster-recovery/argocd/deployments.yaml --validate=false || true
fi

# 4. Počkáme na pody
echo ""
echo "⏳ Čakám 30 sekúnd na rozbehnutie podov..."
sleep 30

# 5. Znova skontrolujeme pody
echo ""
echo "📦 [3/8] STAV PODOV PO APLIKÁCII"
kubectl get pods -n lamp
kubectl get pods -n argocd

# 6. Ak pod banky stále nebeží, pozrieme sa na events
echo ""
echo "📜 [4/8] UDALOSTI V NAMESPACE LAMP"
kubectl get events -n lamp --sort-by='.lastTimestamp' | tail -15

# 7. Ak je pod v stave Error alebo CrashLoop, pozrieme logy
BANK_POD=$(kubectl get pods -n lamp -l app=apache-php -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$BANK_POD" ]; then
    echo ""
    echo "📋 [5/8] LOGY BANKY (posledných 20)"
    kubectl logs -n lamp $BANK_POD --all-containers --tail=20 2>/dev/null || echo "Žiadne logy"
fi

# 8. Oprava image pre phpfpm-exporter (ak pod beží ale vracia 503)
if [ -n "$BANK_POD" ]; then
    CURRENT_IMAGE=$(kubectl get deployment apache-php -n lamp -o jsonpath='{.spec.template.spec.containers[?(@.name=="phpfpm-exporter")].image}' 2>/dev/null)
    if [ "$CURRENT_IMAGE" != "hipages/php-fpm_exporter:2" ]; then
        echo ""
        echo "🔄 [6/8] OPRAVA IMAGE PHPFPM-EXPORTER NA hipages/php-fpm_exporter:2"
        kubectl patch deployment apache-php -n lamp --type='json' -p='[{"op":"replace","path":"/spec/template/spec/containers/3/image","value":"hipages/php-fpm_exporter:2"}]'
        kubectl rollout restart deployment/apache-php -n lamp
        sleep 10
    fi
fi

# 9. Oprava ArgoCD (--insecure a ingress anotácia)
ARGOCD_POD=$(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$ARGOCD_POD" ]; then
    ARGS=$(kubectl get deployment argocd-server -n argocd -o jsonpath='{.spec.template.spec.containers[0].args}' 2>/dev/null)
    if [[ "$ARGS" != *"--insecure"* ]]; then
        echo ""
        echo "🔄 [7/8] PRIDANIE --insecure DO ARGOCD-SERVER"
        kubectl patch deployment argocd-server -n argocd --type='json' -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--insecure"}]'
        kubectl rollout restart deployment/argocd-server -n argocd
    fi
    
    # Ingress anotácia
    ANNOT=$(kubectl get ingress argocd-final -n argocd -o jsonpath='{.metadata.annotations.nginx\.ingress\.kubernetes\.io/backend-protocol}' 2>/dev/null)
    if [ "$ANNOT" != "HTTP" ]; then
        echo ""
        echo "🌐 PRIDANIE ANOTÁCIE backend-protocol=HTTP NA ARGOCD INGRESS"
        kubectl annotate ingress argocd-final -n argocd nginx.ingress.kubernetes.io/backend-protocol=HTTP --overwrite
    fi
fi

# 10. Záverečný test
echo ""
echo "🌐 [8/8] TESTOVANIE WEBOV"
for url in bank.34.89.208.249.nip.io argocd.34.89.208.249.nip.io grafana.34.89.208.249.nip.io alertmanager.34.89.208.249.nip.io kibana.34.89.208.249.nip.io prometheus.34.89.208.249.nip.io nginx.34.89.208.249.nip.io web.34.89.208.249.nip.io; do
    echo -n "http://$url ... "
    curl -s -o /dev/null -w "%{http_code}\n" --max-time 5 http://$url
done

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ DEBUG DOKONČENÝ"
echo "═══════════════════════════════════════════════════════════════"
