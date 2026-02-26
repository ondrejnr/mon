#!/bin/bash
echo "═══════════════════════════════════════════════════════════════"
echo "🔍 KONTROLA PODĽA POSLEDNÉHO FUNKČNÉHO STAVU"
echo "═══════════════════════════════════════════════════════════════"

# 1. Banka - skontroluj deployment
echo ""
echo "🏦 [1/6] BANKA - KONTROLA DEPLOYMENTU"
kubectl get deployment apache-php -n lamp -o yaml | grep -A5 "image:" | grep -E "apache|phpfpm|exporter"

# 2. Banka - skontroluj či je správny image pre phpfpm-exporter
echo ""
echo "🔍 [2/6] BANKA - SPRÁVNY IMAGE PRE PHPFPM-EXPORTER (mal by byť hipages/php-fpm_exporter:2)"
kubectl get deployment apache-php -n lamp -o jsonpath='{.spec.template.spec.containers[?(@.name=="phpfpm-exporter")].image}' && echo ""

# 3. Banka - skontroluj index.php
echo ""
echo "📄 [3/6] BANKA - OBSAH INDEX.PHP"
POD=$(kubectl get pods -n lamp -l app=apache-php -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$POD" ]; then
    kubectl exec -n lamp $POD -c apache -- cat /var/www/html/index.php 2>/dev/null || echo "❌ index.php neexistuje"
else
    echo "❌ Pod banky neexistuje"
fi

# 4. ArgoCD - skontroluj argumenty servera
echo ""
echo "🚀 [4/6] ARGOCD - KONTROLA ARGUMENTOV (mal by byť --insecure)"
kubectl get deployment argocd-server -n argocd -o jsonpath='{.spec.template.spec.containers[0].args}' && echo ""

# 5. ArgoCD - skontroluj ingress anotácie
echo ""
echo "🌐 [5/6] ARGOCD - KONTROLA INGRESS ANOTÁCIÍ"
kubectl get ingress argocd-final -n argocd -o yaml | grep -A5 "annotations"

# 6. Ingress controller - typ služby
echo ""
echo "⚙️ [6/6] INGRESS CONTROLLER - TYP SLUŽBY (mal by byť LoadBalancer)"
kubectl get svc ingress-nginx-controller -n ingress-nginx
echo ""
echo "Externá IP (ak je LoadBalancer):"
kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "❌ Žiadna externá IP"

echo ""
echo "═══════════════════════════════════════════════════════════════"
