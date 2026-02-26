echo "=== VSETKY INGRESS ADRESY ==="
kubectl get ingress -A -o custom-columns="NS:.metadata.namespace,NAME:.metadata.name,HOST:.spec.rules[*].host,SVC:.spec.rules[*].http.paths[*].backend.service.name"

echo "" && echo "=== KIBANA INGRESS ==="
kubectl get ingress -A | grep -i kibana

echo "" && echo "=== NGINX/APACHE INGRESS ==="
kubectl get ingress -A | grep -iE "nginx|apache|web"

echo "" && echo "=== HLADAM VSETKY MOZNE WEBY V NAMESPACOCH ==="
for ns in web web-stack lamp logging monitoring; do
  echo "--- $ns ---"
  kubectl get ingress -n $ns 2>/dev/null || echo "  žiadny ingress"
done
