#!/bin/bash
set -e
echo "═══════════════════════════════════════════════════════════════"
echo "🔄 OBNOVA LAMP A ARGOCD Z DISASTER-RECOVERY"
echo "═══════════════════════════════════════════════════════════════"

# 1. Obnova namespace lamp
echo ""
echo "📁 [1/4] OBNOVA NAMESPACE LAMP"
kubectl apply -f /home/ondrejko_gulkas/mon/disaster-recovery/lamp/

# 2. Obnova namespace argocd
echo ""
echo "📁 [2/4] OBNOVA NAMESPACE ARGOCD"
kubectl apply -f /home/ondrejko_gulkas/mon/disaster-recovery/argocd/

# 3. Obnova ArgoCD aplikácií (ak existujú)
if [ -f /home/ondrejko_gulkas/mon/disaster-recovery/argocd-applications.yaml ]; then
    echo ""
    echo "📁 [3/4] OBNOVA ARGOCD APLIKÁCIÍ"
    kubectl apply -f /home/ondrejko_gulkas/mon/disaster-recovery/argocd-applications.yaml
fi

# 4. Počkanie na rozbehnutie podov
echo ""
echo "⏳ [4/4] ČAKÁM 60 SEKÚND NA ROZBEHNUTIE PODOV..."
sleep 60

# 5. Oprava image pre banku (ak je potrebné)
echo ""
echo "🔧 KONTROLA IMAGE PRE BANKU"
DEPLOY=$(kubectl get deployment -n lamp apache-php -o jsonpath='{.spec.template.spec.containers[?(@.name=="phpfpm-exporter")].image}' 2>/dev/null)
if [ "$DEPLOY" != "hipages/php-fpm_exporter:2" ]; then
    echo "   ❌ Image je '$DEPLOY', opravujem na hipages/php-fpm_exporter:2"
    kubectl patch deployment apache-php -n lamp --type='json' -p='[{"op":"replace","path":"/spec/template/spec/containers/3/image","value":"hipages/php-fpm_exporter:2"}]'
    kubectl rollout restart deployment/apache-php -n lamp
else
    echo "   ✅ Image je správny"
fi

# 6. Vytvorenie index.php (ak chýba)
echo ""
echo "📄 KONTROLA INDEX.PHP"
POD=$(kubectl get pods -n lamp -l app=apache-php -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$POD" ]; then
    if ! kubectl exec -n lamp $POD -c apache -- test -f /var/www/html/index.php &>/dev/null; then
        echo "   ❌ index.php neexistuje, vytváram"
        kubectl exec -n lamp $POD -c apache -- sh -c "echo '<?php phpinfo(); ?>' > /var/www/html/index.php"
    else
        echo "   ✅ index.php existuje"
    fi
fi

# 7. Oprava ArgoCD ingress anotácie
echo ""
echo "🌐 KONTROLA ARGOCD INGRESS ANOTÁCIE"
if kubectl get ingress argocd-final -n argocd &>/dev/null; then
    ANNOT=$(kubectl get ingress argocd-final -n argocd -o jsonpath='{.metadata.annotations.nginx\.ingress\.kubernetes\.io/backend-protocol}')
    if [ "$ANNOT" != "HTTP" ]; then
        echo "   ❌ Anotácia chýba, nastavujem"
        kubectl annotate ingress argocd-final -n argocd nginx.ingress.kubernetes.io/backend-protocol=HTTP --overwrite
    else
        echo "   ✅ Anotácia je správna"
    fi
else
    echo "   ⚠️ Ingress argocd-final neexistuje, preskakujem"
fi

# 8. Záverečný test
echo ""
echo "🌐 TESTOVANIE WEBOV:"
for url in bank.34.89.208.249.nip.io argocd.34.89.208.249.nip.io; do
    echo -n "http://$url ... "
    curl -s -o /dev/null -w "%{http_code}\n" --max-time 5 http://$url
done

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ OBNOVA DOKONČENÁ"
echo "═══════════════════════════════════════════════════════════════"
