echo "=== PODS STATUS ==="
kubectl get pods -A | grep -vE "Running|Completed"

echo "" && echo "=== ARGOCD APPS ==="
kubectl get applications -A -o custom-columns="NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status"

echo "" && echo "=== ENDPOINTS MONITORING ==="
kubectl get endpoints -n monitoring

echo "" && echo "=== ALERTMANAGER POD ==="
kubectl get pods -n monitoring | grep alert

echo "" && echo "=== INGRESS NGINX STATUS ==="
kubectl get pods -n ingress-nginx | grep Running

echo "" && echo "=== HTTP TESTY ==="
for url in argocd.34.89.208.249.nip.io bank.34.89.208.249.nip.io grafana.34.89.208.249.nip.io alertmanager.34.89.208.249.nip.io prometheus.34.89.208.249.nip.io; do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://$url)
  echo "  $code → http://$url"
done
