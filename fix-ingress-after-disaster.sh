#!/bin/bash
set -e
echo "=== OBNOVA INGRESS CONTROLLER PO HAVÁRII ==="
kubectl apply -f /home/ondrejko_gulkas/mon/disaster-recovery/ingress-nginx/
echo "Čakám na spustenie Ingress controlleru..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=ingress-nginx \
  --timeout=120s
echo "✅ Ingress controller beží."
sleep 10
echo "=== KONTROLA INGRESS IP ADRIES ==="
kubectl get ingress -A
echo "=== TESTOVANIE WEBOV ==="
for url in alertmanager.34.89.208.249.nip.io grafana.34.89.208.249.nip.io kibana.34.89.208.249.nip.io nginx.34.89.208.249.nip.io prometheus.34.89.208.249.nip.io web.34.89.208.249.nip.io; do
  echo -n "http://$url ... "
  curl -s -o /dev/null -w "%{http_code}\n" --max-time 5 http://$url
done
