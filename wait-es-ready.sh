echo "=== ES POD STATUS ==="
kubectl get pods -n logging -l app=elasticsearch

echo "" && echo "=== ES LOGY ==="
kubectl logs -n logging -l app=elasticsearch --tail=20 2>/dev/null | grep -E "started|error|ready|Exception|bound|cluster"

echo "" && echo "=== CAKAM AZ ES READY ==="
until kubectl exec -n logging -l app=elasticsearch -- curl -s http://localhost:9200/_cluster/health 2>/dev/null | grep -q '"status"'; do
  echo "  ES nie je ready, cakam 10s..."
  sleep 10
done
echo "✅ ES ready!"

echo "" && echo "=== ES HEALTH ==="
kubectl exec -n logging -l app=elasticsearch -- curl -s http://localhost:9200/_cluster/health 2>/dev/null

echo "" && echo "=== KIBANA TEST ==="
sleep 30
curl -s -o /dev/null -w "KIBANA: %{http_code}\n" http://kibana.34.89.208.249.nip.io
