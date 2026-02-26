echo "=== KIBANA LOGY ==="
kubectl logs -n logging deployment/kibana --tail=30

echo "" && echo "=== KIBANA HEALTH PRIAMO ==="
kubectl exec -n logging deployment/kibana -- curl -s http://localhost:5601/api/status 2>/dev/null | python3 -m json.tool 2>/dev/null | head -20

echo "" && echo "=== KIBANA ENV - ELASTICSEARCH URL ==="
kubectl get deployment kibana -n logging -o jsonpath='{.spec.template.spec.containers[0].env}' | python3 -m json.tool 2>/dev/null

echo "" && echo "=== ELASTICSEARCH EXISTUJE? ==="
kubectl get pods -n logging | grep elastic
kubectl get svc elasticsearch -n logging
curl -s http://$(kubectl get svc elasticsearch -n logging -o jsonpath='{.spec.clusterIP}'):9200 2>/dev/null | head -5
