echo "=== KIBANA POD IP ==="
kubectl get pods -n logging -o wide

echo "" && echo "=== PRIAMY TEST NA KIBANA POD ==="
kubectl exec -n logging deployment/kibana -- wget -qO- http://localhost:5601/api/status 2>/dev/null | head -5

echo "" && echo "=== INGRESS NGINX LOGY PRE KIBANA ==="
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=5 | grep kibana

echo "" && echo "=== VSETKY NETWORK POLICIES V LOGGING ==="
kubectl get networkpolicy -n logging

echo "" && echo "=== MAZEM VSETKY NETWORK POLICIES V LOGGING ==="
kubectl delete networkpolicy --all -n logging
sleep 5
curl -s -o /dev/null -w "KIBANA bez NP: %{http_code}\n" http://kibana.34.89.208.249.nip.io

echo "" && echo "=== KIBANA INGRESS DETAIL ==="
kubectl get ingress kibana-ingress -n logging -o yaml | grep -A10 "rules:"
