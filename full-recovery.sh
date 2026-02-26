#!/bin/bash
set -e
echo "═══════════════════════════════════════════════════════════════"
echo "🚀 KOMPLETNÁ OBNOVA PO HAVÁRII"
echo "═══════════════════════════════════════════════════════════════"

# 1. Obnovenie všetkých namespace a aplikácií zo zálohy
if [ -f /home/ondrejko_gulkas/mon/disaster-recovery/restore.sh ]; then
    /home/ondrejko_gulkas/mon/disaster-recovery/restore.sh
else
    echo "❌ Restore skript neexistuje!"
    exit 1
fi

# 2. Oprava ingress-nginx service na LoadBalancer a externalIP
echo "🔧 Nastavujem ingress-nginx service na LoadBalancer..."
kubectl patch svc ingress-nginx-controller -n ingress-nginx -p '{"spec":{"type":"LoadBalancer"}}' 2>/dev/null || true

NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[0].address}')
echo "🔧 Pridávam externalIP $NODE_IP do service..."
kubectl patch svc ingress-nginx-controller -n ingress-nginx -p "{\"spec\":{\"externalIPs\":[\"$NODE_IP\"]}}"

# 3. Čakám na rozbehnutie podov
echo "⏳ Čakám 60 sekúnd na naštartovanie aplikácií..."
sleep 60

# 4. Kontrola
echo "📦 Stav podov:"
kubectl get pods -A | grep -v Running | grep -v Completed || echo "Všetky pody OK"

echo "🌐 Testovanie webov:"
for url in alertmanager.34.89.208.249.nip.io grafana.34.89.208.249.nip.io kibana.34.89.208.249.nip.io bank.34.89.208.249.nip.io nginx.34.89.208.249.nip.io web.34.89.208.249.nip.io; do
  echo -n "http://$url ... "
  curl -s -o /dev/null -w "%{http_code}\n" --max-time 5 http://$url
done

echo "═══════════════════════════════════════════════════════════════"
