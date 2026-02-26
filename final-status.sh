echo "=== FINALNA KONTROLA VSETKYCH WEBOV ==="
for url in bank.34.89.208.249.nip.io grafana.34.89.208.249.nip.io alertmanager.34.89.208.249.nip.io prometheus.34.89.208.249.nip.io argocd.34.89.208.249.nip.io; do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://$url)
  [[ "$code" =~ ^(200|301|302)$ ]] && icon="✅" || icon="❌"
  echo "  $icon $code → http://$url"
done

echo "" && echo "=== PODS ==="
kubectl get pods -A | grep -vE "Running|Completed" || echo "✅ Vsetky pody Running"

echo "" && echo "=== ARGOCD APPS ==="
kubectl get applications -A -o custom-columns="NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status"
