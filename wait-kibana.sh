echo "=== PODY ==="
kubectl get pods -n logging

echo "" && echo "=== CAKAM 60s NA KIBANA INIT ==="
sleep 60

echo "" && echo "=== KIBANA LOGY ==="
kubectl logs -n logging -l app=kibana --tail=10 2>/dev/null | grep -E "error|ready|running|status|http"

echo "" && echo "=== HTTP TEST ==="
curl -s -o /dev/null -w "KIBANA: %{http_code}\n" http://kibana.34.89.208.249.nip.io

echo "" && echo "=== VSETKY WEBY ==="
for url in bank.34.89.208.249.nip.io grafana.34.89.208.249.nip.io alertmanager.34.89.208.249.nip.io prometheus.34.89.208.249.nip.io argocd.34.89.208.249.nip.io kibana.34.89.208.249.nip.io web.34.89.208.249.nip.io nginx.34.89.208.249.nip.io; do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://$url)
  [[ "$code" =~ ^(200|301|302)$ ]] && icon="✅" || icon="❌"
  echo "  $icon $code → http://$url"
done
