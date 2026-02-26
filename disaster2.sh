echo "🚨 KATASTROFA 2 - MAZEM VSETKO"

echo "=== MAZEM NAMESPACES ==="
kubectl delete namespace lamp logging monitoring web web-stack ingress-nginx --force 2>/dev/null &
echo "=== MAZEM ARGOCD APPS ==="
kubectl delete applications --all -n argocd 2>/dev/null

echo "=== CAKAM AZ VSETKO ZMIZNE ==="
wait
sleep 30 && kubectl get pods -A

echo "" && echo "💀 HTTP TESTY PO KATASTROFE ==="
for url in bank.34.89.208.249.nip.io grafana.34.89.208.249.nip.io alertmanager.34.89.208.249.nip.io prometheus.34.89.208.249.nip.io argocd.34.89.208.249.nip.io kibana.34.89.208.249.nip.io web.34.89.208.249.nip.io nginx.34.89.208.249.nip.io; do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://$url)
  [[ "$code" =~ ^(200|301|302)$ ]] && icon="✅" || icon="💀"
  echo "  $icon $code → http://$url"
done

echo "" && echo "🔄 SPUSTAM RECOVERY ==="
/home/ondrejko_gulkas/mon/disaster-recovery/restore.sh
