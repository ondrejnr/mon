echo "=== ARGOCD SYNC STATUS ==="
kubectl get applications -A -o custom-columns="NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status"

echo "" && echo "=== BANKA POD ==="
kubectl get pods -n lamp && kubectl get endpoints apache-php -n lamp

echo "" && echo "=== GRAFANA INGRESS PORT (po ArgoCD sync) ==="
kubectl get ingress grafana-ingress -n monitoring -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.port.number}' && echo ""

echo "" && echo "=== GRAFANA V GIT - PORT ==="
grep -A2 "grafana-ingress" /home/ondrejko_gulkas/mon/ansible/clusters/my-cluster/monitoring/setup.yaml | grep number

echo "" && echo "=== BANKA IMAGE V GIT ==="
grep "php-fpm" /home/ondrejko_gulkas/mon/k8s-manifests/lamp/apache-php-v14-final.yaml 2>/dev/null || \
find /home/ondrejko_gulkas/mon -name "*.yaml" | xargs grep -l "phpfpm-exporter\|php-fpm-exporter" 2>/dev/null | xargs grep "image:" 2>/dev/null | grep "php-fpm"

echo "" && echo "=== HTTP TESTY ==="
for url in bank.34.89.208.249.nip.io grafana.34.89.208.249.nip.io; do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://$url)
  echo "  $code → http://$url"
done
