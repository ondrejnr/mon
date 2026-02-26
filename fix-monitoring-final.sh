echo "=== GRAFANA - OPRAVA PORTU (80→3000) ==="
kubectl patch ingress grafana-ingress -n monitoring --type=json -p='[
  {"op":"replace","path":"/spec/rules/0/http/paths/0/backend/service/port/number","value":3000}
]'

echo "" && echo "=== ALERTMANAGER SERVICE - EXISTUJE? ==="
kubectl get svc -n monitoring

echo "" && echo "=== ALERTMANAGER POD ==="
kubectl get pods -n monitoring -l app=alertmanager 2>/dev/null || \
kubectl get pods -n monitoring | grep alert

echo "" && echo "=== VYTVÁRAM ALERTMANAGER SERVICE ak chýba ==="
kubectl get svc alertmanager -n monitoring 2>/dev/null || \
kubectl expose deployment alertmanager -n monitoring --port=9093 --target-port=9093 --name=alertmanager 2>/dev/null || \
echo "WARN: alertmanager deployment neexistuje - skontroluj kubectl get all -n monitoring"

kubectl get all -n monitoring

echo "" && echo "=== HTTP TESTY ==="
sleep 5
curl -s -o /dev/null -w "GRAFANA: %{http_code}\n" http://grafana.34.89.208.249.nip.io
curl -s -o /dev/null -w "ALERTMANAGER: %{http_code}\n" http://alertmanager.34.89.208.249.nip.io
curl -s -o /dev/null -w "PROMETHEUS: %{http_code}\n" http://prometheus.34.89.208.249.nip.io
