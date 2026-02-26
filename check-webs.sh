echo "=== VSETKY INGRESS ADRESY ==="
kubectl get ingress -A -o custom-columns="NS:.metadata.namespace,NAME:.metadata.name,HOST:.spec.rules[*].host,TLS:.spec.tls[*].secretName,SERVICE:.spec.rules[*].http.paths[*].backend.service.name"

echo "" && echo "=== HTTP TESTY ==="
for url in $(kubectl get ingress -A -o jsonpath='{.items[*].spec.rules[*].host}'); do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://$url)
  echo "  $code → http://$url"
done

echo "" && echo "=== PODS STATUS ==="
kubectl get pods -A | grep -vE "Running|Completed"

echo "" && echo "=== ENDPOINTS ==="
kubectl get endpoints -A | grep -v "<none>" | grep -v "^NAMESPACE"
