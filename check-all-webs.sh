echo "=== VSETKY INGRESS HOSTY + KIBANA ==="
kubectl get ingress -A -o custom-columns="NS:.metadata.namespace,NAME:.metadata.name,HOST:.spec.rules[*].host"

echo "" && echo "=== KIBANA STATUS ==="
kubectl get pods,svc,ingress -n logging

echo "" && echo "=== HTTP TESTY ==="
HOSTS=$(kubectl get ingress -A -o jsonpath='{range .items[*]}{.spec.rules[*].host}{"\n"}{end}' | sort)
for url in $HOSTS; do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://$url)
  [[ "$code" =~ ^(200|301|302)$ ]] && icon="✅" || icon="❌"
  echo "  $icon $code → http://$url"
done

echo "" && echo "=== KIBANA PRIAMY TEST ==="
curl -s -o /dev/null -w "KIBANA NodePort: %{http_code}\n" --max-time 5 http://34.89.208.249:31243
