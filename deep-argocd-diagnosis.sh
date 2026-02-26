#!/bin/bash
set -e
echo "═══════════════════════════════════════════════════════════════"
echo "🔍 HĹBOKÁ DIAGNOSTIKA ARGOCD - SÚVISLOSTI A ZÁVISLOSTI"
echo "═══════════════════════════════════════════════════════════════"

NAMESPACE="argocd"
HOST="argocd.34.89.208.249.nip.io"
INGRESS_NAME="argocd-final"

echo ""
echo "📦 [1/8] STAV VŠETKÝCH PODOV V ARGOCD NAMESPACE"
kubectl get pods -n $NAMESPACE -o wide

echo ""
echo "📋 [2/8] LOGY ARGOCD-SERVER (posledných 30 riadkov)"
kubectl logs -n $NAMESPACE deployment/argocd-server --tail=30 2>/dev/null || echo "❌ Deployment argocd-server neexistuje alebo nie sú logy"

echo ""
echo "🔌 [3/8] ENDPOINTY PRE SLUŽBY V ARGOCD (ktoré služby majú backend)"
kubectl get endpoints -n $NAMESPACE

echo ""
echo "🌐 [4/8] DETAIL INGRESSU $INGRESS_NAME"
kubectl get ingress $INGRESS_NAME -n $NAMESPACE -o yaml | grep -A20 "rules:" || echo "❌ Ingress neexistuje"

echo ""
echo "⚙️ [5/8] KONTROLA ANOTÁCIÍ INGRESSU (pre backend protocol)"
ANNOT=$(kubectl get ingress $INGRESS_NAME -n $NAMESPACE -o jsonpath='{.metadata.annotations.nginx\.ingress\.kubernetes\.io/backend-protocol}' 2>/dev/null)
if [ "$ANNOT" == "HTTP" ]; then
    echo "✅ Anotácia backend-protocol=HTTP je nastavená"
else
    echo "❌ Anotácia backend-protocol je '$ANNOT' (očakáva sa HTTP)"
fi

echo ""
echo "🔄 [6/8] TESTOVANIE KONEKTIVITY Z INGRESS CONTROLLERA DO ARGOCD-SERVER"
INGRESS_POD=$(kubectl get pods -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$INGRESS_POD" ]; then
    echo "   Ingress pod: $INGRESS_POD"
    echo "   Test na service argocd-server.argocd.svc.cluster.local:80"
    HTTP_CODE=$(kubectl exec -n ingress-nginx $INGRESS_POD -- curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://argocd-server.$NAMESPACE.svc.cluster.local 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" == "200" ] || [ "$HTTP_CODE" == "302" ] || [ "$HTTP_CODE" == "401" ] || [ "$HTTP_CODE" == "403" ]; then
        echo "   ✅ Backend odpovedá s kódom $HTTP_CODE (očakávaný 401/403/200/302)"
    else
        echo "   ❌ Backend odpovedá s kódom $HTTP_CODE (alebo vôbec)"
    fi
else
    echo "❌ Ingress controller pod nenájdený"
fi

echo ""
echo "📡 [7/8] PRIAMY TEST CEZ SERVICE CLUSTER IP (z dočasného podu)"
kubectl run curl-test --image=curlimages/curl -it --rm --restart=Never --namespace=$NAMESPACE -- curl -s -o /dev/null -w "HTTP %{http_code}\n" http://argocd-server:80 2>/dev/null || echo "❌ Service nie je dostupná"

echo ""
echo "🔐 [8/8] KONTROLA ARGUMENTOV ARGOCD-SERVERA"
ARGS=$(kubectl get deployment argocd-server -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].args}' 2>/dev/null)
if [[ "$ARGS" == *"--insecure"* ]]; then
    echo "✅ Argument --insecure je prítomný"
else
    echo "❌ Argument --insecure chýba (môže spôsobovať HTTPS redirect)"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "🔎 SÚHRN A ODPORÚČANIA"
echo "═══════════════════════════════════════════════════════════════"

# Vyhodnotenie
if ! kubectl get deployment argocd-server -n $NAMESPACE &>/dev/null; then
    echo "❌ Deployment argocd-server neexistuje. Je potrebné ho vytvoriť."
elif ! kubectl get pods -n $NAMESPACE | grep -q "argocd-server.*Running"; then
    echo "❌ Pod argocd-server nie je v stave Running. Pozri logy."
else
    # Overíme, či service má endpointy
    EP=$(kubectl get endpoints argocd-server -n $NAMESPACE -o jsonpath='{.subsets}' 2>/dev/null)
    if [ -z "$EP" ] || [ "$EP" == "null" ]; then
        echo "❌ Service argocd-server nemá žiadne endpointy (pod pravdepodobne nie je ready)."
    else
        echo "✅ Service argocd-server má endpointy."
    fi

    # Overíme ingress
    if kubectl get ingress $INGRESS_NAME -n $NAMESPACE &>/dev/null; then
        ADDR=$(kubectl get ingress $INGRESS_NAME -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
        if [ -n "$ADDR" ]; then
            echo "✅ Ingress má priradenú IP: $ADDR"
        else
            echo "❌ Ingress nemá priradenú IP (čaká sa na LoadBalancer)."
        fi
    else
        echo "❌ Ingress $INGRESS_NAME neexistuje."
    fi
fi

echo ""
echo "Ak je všetko v poriadku a ArgoCD stále 404, skontroluj, či nie je problém s cachingom v prehliadači alebo DNS."
echo "Môžeš skúsiť: curl -I http://$HOST"
echo "═══════════════════════════════════════════════════════════════"
