#!/bin/bash
set -e
echo "=== OBNOVA INGRESS-NGINX PO HAVÁRII ==="

# 1. Vytvorenie namespace (ak neexistuje)
kubectl create namespace ingress-nginx --dry-run=client -o yaml | kubectl apply -f -

# 2. Aplikovanie oficiálneho ingress-nginx manifestu
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/baremetal/deploy.yaml

# 3. Počkanie na spustenie controller podu
echo "Čakám na spustenie Ingress controlleru..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=ingress-nginx \
  --timeout=120s

# 4. Zmena služby na LoadBalancer (ak je potrebné)
kubectl patch svc ingress-nginx-controller -n ingress-nginx -p '{"spec":{"type":"LoadBalancer"}}'

# 5. Kontrola IP adries
sleep 10
echo "=== INGRESSY ==="
kubectl get ingress -A

echo "=== TESTOVANIE WEBOV ==="
for url in alertmanager.34.89.208.249.nip.io grafana.34.89.208.249.nip.io kibana.34.89.208.249.nip.io nginx.34.89.208.249.nip.io prometheus.34.89.208.249.nip.io web.34.89.208.249.nip.io; do
  echo -n "http://$url ... "
  curl -s -o /dev/null -w "%{http_code}\n" --max-time 5 http://$url
done
