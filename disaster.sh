echo "🚨 SIMULUJEM KATASTROFU - MAZEM VSETKO"

echo "=== MAZEM NAMESPACES ==="
kubectl delete namespace lamp --force 2>/dev/null &
kubectl delete namespace logging --force 2>/dev/null &
kubectl delete namespace monitoring --force 2>/dev/null &
kubectl delete namespace web --force 2>/dev/null &
kubectl delete namespace web-stack --force 2>/dev/null &
kubectl delete namespace ingress-nginx --force 2>/dev/null &
wait

echo "=== MAZEM ARGOCD APPS ==="
kubectl delete applications --all -n argocd 2>/dev/null

echo "=== CAKAM AZ VSETKO ZMIZNE ==="
sleep 20 && kubectl get pods -A

echo "" && echo "=== HTTP TESTY PO KATASTROFE ==="
for url in bank.34.89.208.249.nip.io grafana.34.89.208.249.nip.io alertmanager.34.89.208.249.nip.io prometheus.34.89.208.249.nip.io argocd.34.89.208.249.nip.io kibana.34.89.208.249.nip.io web.34.89.208.249.nip.io nginx.34.89.208.249.nip.io; do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://$url)
  [[ "$code" =~ ^(200|301|302)$ ]] && icon="✅" || icon="💀"
  echo "  $icon $code → http://$url"
done

echo "" && echo "=== SPUSTAM RECOVERY ==="
/home/ondrejko_gulkas/mon/disaster-recovery/restore.sh
