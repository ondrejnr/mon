echo "=== VSETKY INGRESS HOSTY A IP ==="
kubectl get ingress -A -o custom-columns="NS:.metadata.namespace,NAME:.metadata.name,HOST:.spec.rules[*].host,IP:.status.loadBalancer.ingress[*].ip,SVC:.spec.rules[*].http.paths[*].backend.service.name"

echo "" && echo "=== SKUTOCNA EXTERNAL IP NODEU ==="
kubectl get nodes -o wide

echo "" && echo "=== HTTP TESTY ==="
for url in $(kubectl get ingress -A -o jsonpath='{range .items[*]}{.spec.rules[*].host}{"\n"}{end}' | sort -u); do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://$url)
  [[ "$code" =~ ^(200|301|302)$ ]] && icon="✅" || icon="❌"
  echo "  $icon $code → http://$url"
done
