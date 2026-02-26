#!/bin/bash
echo "═══════════════════════════════════════════════════════════════"
echo "🔍 DIAGNOSTIKA - PREČO WEBY STALE NEFUNGUJÚ"
echo "═══════════════════════════════════════════════════════════════"

# 1. Skontroluj service ingress-nginx-controller
echo ""
echo "📦 [1/6] SERVICE INGRESS-NGINX-CONTROLLER"
kubectl get svc -n ingress-nginx ingress-nginx-controller
EXTERNAL_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
if [ -z "$EXTERNAL_IP" ]; then
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[0].address}')
    echo "⚠️ Service nemá pridelenú externú IP. Node IP je $NODE_IP"
    echo "   Skús manuálne nastaviť: kubectl patch svc ingress-nginx-controller -n ingress-nginx -p '{\"spec\":{\"externalIPs\":[\"$NODE_IP\"]}}'"
else
    echo "✅ Externá IP: $EXTERNAL_IP"
fi

# 2. Skontroluj, či ingressy majú pridelenú IP adresu
echo ""
echo "🌐 [2/6] INGRESSY A ICH ADRESY"
kubectl get ingress -A

# 3. Otestuj priamo na node IP (alebo external IP) s portom 80
TARGET_IP=${EXTERNAL_IP:-$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[0].address}')}
echo ""
echo "🔌 [3/6] TESTOVANIE PRIAMO NA IP $TARGET_IP:80"
curl -s -o /dev/null -w "HTTP %{http_code}\n" --max-time 5 http://$TARGET_IP || echo "❌ Nedostupné"

# 4. Skontroluj, či vôbec nejaký backend pod je ready
echo ""
echo "📦 [4/6] STAV BACKEND PODOV"
for ns in lamp monitoring logging web web-stack; do
    echo "--- $ns ---"
    kubectl get pods -n $ns | grep -v Running || echo "  Všetky bežia"
done

# 5. Skontroluj logy ingress controlleru (posledných 10)
echo ""
echo "📜 [5/6] LOGY INGRESS CONTROLLERU"
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=10 2>/dev/null || echo "Žiadne logy"

# 6. Skús curl na konkrétny web (napr. bank) cez node IP s hlavičkou Host
echo ""
echo "🌍 [6/6] TESTOVANIE S HLAVIČKOU HOST (priamo na IP)"
curl -s -o /dev/null -w "bank: %{http_code}\n" -H "Host: bank.34.89.208.249.nip.io" http://$TARGET_IP
curl -s -o /dev/null -w "grafana: %{http_code}\n" -H "Host: grafana.34.89.208.249.nip.io" http://$TARGET_IP
curl -s -o /dev/null -w "kibana: %{http_code}\n" -H "Host: kibana.34.89.208.249.nip.io" http://$TARGET_IP

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ DIAGNOSTIKA DOKONČENÁ"
echo "═══════════════════════════════════════════════════════════════"
