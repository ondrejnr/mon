#!/bin/bash
set -e
echo "═══════════════════════════════════════════════════════════════"
echo "🚀 KOMPLETNÁ OBNOVA PO HAVÁRII"
echo "═══════════════════════════════════════════════════════════════"

# 1. Oprava ingress-nginx service
echo ""
echo "🔧 [1/6] OPRAVA INGRESS-NGINX SERVICE (LoadBalancer + externalIP)"
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[0].address}')
kubectl patch svc ingress-nginx-controller -n ingress-nginx -p '{"spec":{"type":"LoadBalancer"}}' 2>/dev/null || true
kubectl patch svc ingress-nginx-controller -n ingress-nginx -p "{\"spec\":{\"externalIPs\":[\"$NODE_IP\"]}}"
echo "✅ Service opravená, externalIP = $NODE_IP"

# 2. Kontrola existencie kritických namespace a podov
echo ""
echo "📦 [2/6] KONTROLA NAMESPACOV A PODOV"
for ns in argocd lamp logging monitoring web web-stack; do
    if kubectl get namespace $ns &>/dev/null; then
        echo "   ✅ Namespace $ns existuje"
        pods=$(kubectl get pods -n $ns -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
        if [ -z "$pods" ]; then
            echo "      ⚠️  Žiadne pody v $ns – obnovujem z disaster-recovery..."
            kubectl apply -f /home/ondrejko_gulkas/mon/disaster-recovery/$ns/ 2>/dev/null || true
        else
            echo "      ✅ Pody existujú"
        fi
    else
        echo "   ❌ Namespace $ns neexistuje – vytváram a obnovujem..."
        kubectl create namespace $ns
        kubectl apply -f /home/ondrejko_gulkas/mon/disaster-recovery/$ns/ 2>/dev/null || true
    fi
done

# 3. Špeciálne pre ArgoCD – aplikácie
echo ""
echo "🚀 [3/6] OBNOVA ARGOCD APLIKÁCIÍ"
if [ -f /home/ondrejko_gulkas/mon/disaster-recovery/argocd-applications.yaml ]; then
    kubectl apply -f /home/ondrejko_gulkas/mon/disaster-recovery/argocd-applications.yaml
    echo "✅ ArgoCD aplikácie obnovené"
else
    echo "⚠️ Súbor argocd-applications.yaml neexistuje, preskakujem"
fi

# 4. Počkanie na rozbehnutie podov
echo ""
echo "⏳ [4/6] ČAKÁM 60 SEKÚND NA ROZBEHNUTIE PODOV..."
sleep 60

# 5. Záverečná kontrola
echo ""
echo "🔍 [5/6] STAV PODOV (nie Running):"
kubectl get pods -A | grep -v Running | grep -v Completed || echo "✅ Všetky pody OK"

# 6. Testovanie webov
echo ""
echo "🌐 [6/6] TESTOVANIE WEBOV:"
for url in alertmanager.34.89.208.249.nip.io grafana.34.89.208.249.nip.io kibana.34.89.208.249.nip.io bank.34.89.208.249.nip.io nginx.34.89.208.249.nip.io web.34.89.208.249.nip.io argocd.34.89.208.249.nip.io; do
    echo -n "http://$url ... "
    curl -s -o /dev/null -w "%{http_code}\n" --max-time 5 http://$url || echo "000"
done

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ OBNOVA DOKONČENÁ"
echo "═══════════════════════════════════════════════════════════════"
