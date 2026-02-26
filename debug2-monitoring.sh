echo "=== GRAFANA INGRESS AKTUALNY PORT ==="
kubectl get ingress grafana-ingress -n monitoring -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.port.number}' && echo ""

echo "" && echo "=== INGRESS NGINX UPSTREAM PRE GRAFANU ==="
kubectl exec -n ingress-nginx deployment/ingress-nginx-controller -- cat /etc/nginx/nginx.conf 2>/dev/null | grep -A5 "grafana" | head -30

echo "" && echo "=== NETWORK POLICY - INGRESS CONTROLLER IP vs NAMESPACE LABEL ==="
kubectl get namespace ingress-nginx --show-labels
kubectl get pods -n ingress-nginx -o wide | grep Running

echo "" && echo "=== TEST: CURL Z INGRESS NGINX PRIAMO NA GRAFANA ==="
kubectl exec -n ingress-nginx deployment/ingress-nginx-controller -- wget -qO- http://10.42.0.14:3000/api/health 2>/dev/null || \
kubectl exec -n ingress-nginx deployment/ingress-nginx-controller -- curl -s http://10.42.0.14:3000/api/health 2>/dev/null

echo "" && echo "=== GRAFANA SVC DETAIL ==="
kubectl get svc grafana -n monitoring -o yaml | grep -A15 "spec:"

echo "" && echo "=== VŠETKY MONITORING SERVICES ==="
kubectl get svc -n monitoring
