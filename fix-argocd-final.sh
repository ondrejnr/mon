#!/bin/bash
set -e
echo "═══════════════════════════════════════════════════════════════"
echo "🔧 ZÁVEREČNÁ OPRAVA ARGOCD – ODSTRÁNENIE PRESMEROVANIA"
echo "═══════════════════════════════════════════════════════════════"

NAMESPACE="argocd"
INGRESS_NAME="argocd-final"
HOST="argocd.34.89.208.249.nip.io"

# 1. Skontrolujeme a pridáme --insecure do deploymentu
echo ""
echo "📦 [1/4] Kontrola argumentov argocd-server..."
CURRENT_ARGS=$(kubectl get deployment argocd-server -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].args}' 2>/dev/null)
if [[ "$CURRENT_ARGS" != *"--insecure"* ]]; then
    echo "   ❌ --insecure chýba, pridávam..."
    kubectl patch deployment argocd-server -n $NAMESPACE --type='json' -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--insecure"}]'
else
    echo "   ✅ --insecure je prítomný"
fi

# 2. Skontrolujeme anotáciu ingressu
echo ""
echo "🌐 [2/4] Kontrola anotácie ingressu..."
CURRENT_ANNOT=$(kubectl get ingress $INGRESS_NAME -n $NAMESPACE -o jsonpath='{.metadata.annotations.nginx\.ingress\.kubernetes\.io/backend-protocol}' 2>/dev/null)
if [ "$CURRENT_ANNOT" != "HTTP" ]; then
    echo "   ❌ Anotácia backend-protocol nie je HTTP, opravujem..."
    kubectl annotate ingress $INGRESS_NAME -n $NAMESPACE nginx.ingress.kubernetes.io/backend-protocol=HTTP --overwrite
else
    echo "   ✅ Anotácia backend-protocol=HTTP je správna"
fi

# 3. Reštartujeme deployment, aby sa zmeny aplikovali
echo ""
echo "🔄 [3/4] Reštartujem argocd-server..."
kubectl rollout restart deployment/argocd-server -n $NAMESPACE
echo "   Čakám 20 sekúnd na rozbehnutie..."
sleep 20

# 4. Testujeme
echo ""
echo "🌍 [4/4] Testovanie ArgoCD"
echo "   http://$HOST ... "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://$HOST)
if [ "$HTTP_CODE" == "200" ] || [ "$HTTP_CODE" == "302" ] || [ "$HTTP_CODE" == "401" ] || [ "$HTTP_CODE" == "403" ]; then
    echo "   ✅ HTTP $HTTP_CODE – ArgoCD je dostupné (očakáva sa prihlasovacia stránka)"
else
    echo "   ❌ HTTP $HTTP_CODE – stále nie je v poriadku"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "🎉 Hotovo. Ak sa stále zobrazuje presmerovanie, skúste vymazať cache prehliadača."
echo "═══════════════════════════════════════════════════════════════"
