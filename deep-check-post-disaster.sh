echo "🔍 HLBOKA KONTROLA PO KATASTROFE - $(date)"
D="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "" && echo "$D" && echo "🚨 UNHEALTHY PODY"
kubectl get pods -A | grep -vE "Running|Completed" || echo "✅ Vsetky pody OK"

echo "" && echo "$D" && echo "📊 VSETKY PODY"
kubectl get pods -A

echo "" && echo "$D" && echo "🔌 SERVICES BEZ ENDPOINTOV"
for ns in lamp logging monitoring web web-stack ingress-nginx argocd; do
  for svc in $(kubectl get svc -n $ns -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    ep=$(kubectl get endpoints $svc -n $ns -o jsonpath='{.subsets}' 2>/dev/null)
    t=$(kubectl get svc $svc -n $ns -o jsonpath='{.spec.type}' 2>/dev/null)
    [[ "$t" == "ExternalName" ]] && continue
    [[ -z "$ep" || "$ep" == "null" ]] && echo "  ❌ $ns/$svc → NO ENDPOINTS"
  done
done

echo "" && echo "$D" && echo "🚀 ARGOCD APPS"
kubectl get applications -A -o custom-columns="NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status" 2>/dev/null || echo "❌ ArgoCD apps nenajdene"

echo "" && echo "$D" && echo "🌐 INGRESS"
kubectl get ingress -A -o custom-columns="NS:.metadata.namespace,NAME:.metadata.name,HOST:.spec.rules[*].host,SVC:.spec.rules[*].http.paths[*].backend.service.name" 2>/dev/null

echo "" && echo "$D" && echo "🔐 TLS CERTY"
for ns in lamp logging monitoring; do
  for s in $(kubectl get secrets -n $ns --field-selector=type=kubernetes.io/tls -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    c=$(kubectl get secret $s -n $ns -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d 2>/dev/null)
    [ -n "$c" ] && echo "  📜 $ns/$s → $(echo "$c" | openssl x509 -noout -enddate 2>/dev/null)"
  done
done

echo "" && echo "$D" && echo "🌍 HTTP TESTY"
for url in bank.34.89.208.249.nip.io grafana.34.89.208.249.nip.io alertmanager.34.89.208.249.nip.io prometheus.34.89.208.249.nip.io argocd.34.89.208.249.nip.io kibana.34.89.208.249.nip.io web.34.89.208.249.nip.io nginx.34.89.208.249.nip.io; do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://$url)
  [[ "$code" =~ ^(200|301|302)$ ]] && icon="✅" || icon="❌"
  echo "  $icon $code → http://$url"
done

echo "" && echo "$D" && echo "✅ HOTOVO - $(date)"
