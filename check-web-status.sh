echo "=== VSETKY INGRESS HOSTY ==="
kubectl get ingress -A -o jsonpath='{range .items[*]}{.spec.rules[*].host}{"\n"}{end}' | sort

echo "" && echo "=== HTTP TESTY VSETKYCH HOSTOV ==="
for url in $(kubectl get ingress -A -o jsonpath='{range .items[*]}{.spec.rules[*].host}{"\n"}{end}' | sort); do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://$url)
  [[ "$code" =~ ^(200|301|302)$ ]] && icon="✅" || icon="❌"
  echo "  $icon $code → http://$url"
done

echo "" && echo "=== PODS STATUS ==="
kubectl get pods -A | grep -vE "Running|Completed" || echo "✅ Vsetky pody Running"
