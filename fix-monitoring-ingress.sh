echo "=== GRAFANA NETWORK POLICY ==="
kubectl get networkpolicy allow-nginx-ingress-access -n monitoring -o yaml | grep -A20 "ingress:"

echo "" && echo "=== INGRESS CONTROLLER IP ==="
kubectl get pods -n ingress-nginx -o wide | grep Running

echo "" && echo "=== TEST PRIAMY NA POD ==="
kubectl exec -n monitoring deployment/grafana -- wget -qO- http://localhost:3000/api/health 2>/dev/null || \
kubectl port-forward -n monitoring svc/grafana 3001:3000 &
sleep 3 && curl -s http://localhost:3001/api/health && kill %1 2>/dev/null

echo "" && echo "=== INGRESS ANOTACIE ==="
kubectl get ingress grafana-ingress -n monitoring -o yaml | grep -A10 "annotations:"

echo "" && echo "=== PATCH - PRIDAM INGRESS CLASS ANOTACIU ==="
kubectl patch ingress grafana-ingress -n monitoring --type=json -p='[
  {"op":"add","path":"/metadata/annotations/kubernetes.io~1ingress.class","value":"nginx"}
]'
kubectl patch ingress alertmanager-ingress -n monitoring --type=json -p='[
  {"op":"add","path":"/metadata/annotations/kubernetes.io~1ingress.class","value":"nginx"}
]'
kubectl patch ingress prometheus-ingress -n monitoring --type=json -p='[
  {"op":"add","path":"/metadata/annotations/kubernetes.io~1ingress.class","value":"nginx"}
]'

sleep 5
echo "" && echo "=== HTTP TESTY ==="
curl -s -o /dev/null -w "GRAFANA: %{http_code}\n" http://grafana.34.89.208.249.nip.io
curl -s -o /dev/null -w "ALERTMANAGER: %{http_code}\n" http://alertmanager.34.89.208.249.nip.io
curl -s -o /dev/null -w "PROMETHEUS: %{http_code}\n" http://prometheus.34.89.208.249.nip.io
