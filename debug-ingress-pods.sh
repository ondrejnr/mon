#!/bin/bash
set -e
echo "=== DEBUG INGRESS-NGINX PODOV ==="

# 1. Zoznam podov
echo "--- PODY V NAMESPACE ingress-nginx ---"
kubectl get pods -n ingress-nginx

# 2. Events pre každý pod
echo "--- UDALOSTI PRE PODY ---"
for pod in $(kubectl get pods -n ingress-nginx -o jsonpath='{.items[*].metadata.name}'); do
  echo "Pod: $pod"
  kubectl describe pod -n ingress-nginx $pod | grep -A10 "Events:"
  echo ""
done

# 3. Kontrola, či už niekto nepoužíva porty 80/443
echo "--- KONTROLA PORT 80/443 NA NODE ---"
sudo netstat -tulpn | grep -E ':80 |:443 ' || echo "Porty sú voľné"

# 4. Vytvorenie secret pre webhook, ak chýba
echo "--- KONTROLA SECRET PRE WEBHOOK ---"
if ! kubectl get secret -n ingress-nginx ingress-nginx-admission &>/dev/null; then
  echo "Secret ingress-nginx-admission neexistuje, vytváram..."
  kubectl create secret tls ingress-nginx-admission -n ingress-nginx --key=/dev/null --cert=/dev/null
fi

# 5. Reštart deploymentu
echo "--- REŠTART INGRESS CONTROLLER DEPLOYMENTU ---"
kubectl rollout restart deployment/ingress-nginx-controller -n ingress-nginx

# 6. Čakanie a kontrola
echo "Čakám 30 sekúnd..."
sleep 30
kubectl get pods -n ingress-nginx

echo "=== HOTOVO ==="
