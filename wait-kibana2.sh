echo "=== ES HEALTH CEZ KUBECTL EXEC ==="
kubectl exec -n logging deployment/elasticsearch -- \
  wget -qO- http://localhost:9200/_cluster/health 2>/dev/null || \
kubectl exec -n logging deployment/elasticsearch -- \
  bash -c "cat /dev/tcp/localhost/9200" 2>/dev/null || \
echo "exec nefunguje - skusam port-forward"

echo "" && echo "=== ES DOSTUPNOST CEZ SERVICE ==="
kubectl run es-test --image=curlimages/curl --restart=Never --rm -i \
  --namespace=logging \
  -- curl -s http://elasticsearch:9200/_cluster/health 2>/dev/null && echo ""

echo "" && echo "=== KIBANA LOGY - AKTUALNY STAV ==="
kubectl logs -n logging deployment/kibana --tail=5 2>/dev/null

echo "" && echo "=== CAKAM 60s ==="
sleep 60

echo "" && echo "=== KIBANA TEST ==="
curl -s -o /dev/null -w "KIBANA: %{http_code}\n" http://kibana.34.89.208.249.nip.io
kubectl logs -n logging deployment/kibana --tail=5 2>/dev/null | grep -E "ready|error|status|running"
