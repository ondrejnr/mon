#!/bin/bash
echo "🚨 DISASTER RECOVERY - OBNOVUJEM CLUSTER"
OUTDIR=$(dirname "$0")

echo "=== [1] NAMESPACES ==="
kubectl apply -f $OUTDIR/namespaces.yaml

echo "=== [2] ARGOCD ==="
kubectl apply -f $OUTDIR/argocd/ --recursive

echo "=== [3] INGRESS NGINX ==="
kubectl apply -f $OUTDIR/ingress-nginx/ --recursive

echo "=== [4] LAMP ==="
kubectl apply -f $OUTDIR/lamp/ --recursive

echo "=== [5] LOGGING ==="
kubectl apply -f $OUTDIR/logging/ --recursive

echo "=== [6] MONITORING ==="
kubectl apply -f $OUTDIR/monitoring/ --recursive

echo "=== [7] WEB ==="
kubectl apply -f $OUTDIR/web/ --recursive
kubectl apply -f $OUTDIR/web-stack/ --recursive

echo "=== [8] ARGOCD APPS ==="
kubectl apply -f $OUTDIR/argocd-applications.yaml

echo "" && echo "=== CAKAM NA PODY ==="
sleep 30
kubectl get pods -A | grep -vE "Running|Completed"

echo "" && echo "=== HTTP TESTY ==="
for url in bank.34.89.208.249.nip.io grafana.34.89.208.249.nip.io alertmanager.34.89.208.249.nip.io prometheus.34.89.208.249.nip.io argocd.34.89.208.249.nip.io kibana.34.89.208.249.nip.io web.34.89.208.249.nip.io nginx.34.89.208.249.nip.io; do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://$url)
  [[ "$code" =~ ^(200|301|302)$ ]] && icon="✅" || icon="❌"
  echo "  $icon $code → http://$url"
done
