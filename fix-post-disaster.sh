echo "=== [1] INGRESS CONTROLLER - PRECO STUCK ==="
kubectl describe pod -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx | grep -A10 "Events:"

echo "" && echo "=== [2] FORCE RECREATE INGRESS CONTROLLER ==="
kubectl rollout restart deployment/ingress-nginx-controller -n ingress-nginx
echo "  Cakam na ingress-nginx..."
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=ingress-nginx \
  -n ingress-nginx --timeout=120s 2>/dev/null && echo "✅ ingress ready" || echo "❌ stale nie ready"

echo "" && echo "=== [3] APLIKUJEM VSETKY INGRESS ==="
for ns in lamp logging monitoring web web-stack; do
  echo "  Aplikujem $ns ingress..."
  kubectl apply -f /home/ondrejko_gulkas/mon/disaster-recovery/$ns/ingress.yaml 2>/dev/null || echo "  WARN: $ns ingress zlyhal"
done

echo "" && echo "=== [4] ARGOCD SYNC OUTSYNC APPS ==="
for app in monitoring-stack nginx-stack web-stack; do
  kubectl annotate application $app -n argocd argocd.argoproj.io/refresh=hard --overwrite 2>/dev/null
done
sleep 20

echo "" && echo "=== [5] HTTP TESTY ==="
for url in bank.34.89.208.249.nip.io grafana.34.89.208.249.nip.io alertmanager.34.89.208.249.nip.io prometheus.34.89.208.249.nip.io argocd.34.89.208.249.nip.io kibana.34.89.208.249.nip.io web.34.89.208.249.nip.io nginx.34.89.208.249.nip.io; do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://$url)
  [[ "$code" =~ ^(200|301|302)$ ]] && icon="✅" || icon="❌"
  echo "  $icon $code → http://$url"
done
