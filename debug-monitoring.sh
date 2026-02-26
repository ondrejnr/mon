echo "=== INGRESS NGINX LOGY - POSLEDNYCH 20 ==="
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=20

echo "" && echo "=== GRAFANA INGRESS YAML ==="
kubectl get ingress grafana-ingress -n monitoring -o yaml

echo "" && echo "=== NETWORK POLICY DETAIL ==="
kubectl get networkpolicy allow-nginx-ingress-access -n monitoring -o yaml

echo "" && echo "=== INGRESS CONTROLLER POD IP ==="
kubectl get pods -n ingress-nginx -o wide | grep Running

echo "" && echo "=== PRIAMY TEST NA GRAFANA POD ==="
kubectl exec -n monitoring deployment/grafana -- wget -qO- http://localhost:3000/api/health

echo "" && echo "=== GRAFANA ENDPOINT DETAIL ==="
kubectl get endpoints grafana -n monitoring -o yaml | grep -A5 "subsets\|addresses\|ports"
