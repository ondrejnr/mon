echo "=== OPRAVA ES VERZIE V GIT ==="
sed -i 's|elasticsearch:7.17.10|elasticsearch:8.11.0|g' \
  /home/ondrejko_gulkas/mon/ansible/clusters/my-cluster/logging/setup.yaml
sed -i 's|docker.elastic.co/elasticsearch/elasticsearch:7.17.10|docker.elastic.co/elasticsearch/elasticsearch:8.11.0|g' \
  /home/ondrejko_gulkas/mon/ansible/clusters/my-cluster/logging/setup.yaml

echo "=== OVERENIE ==="
grep "elasticsearch" /home/ondrejko_gulkas/mon/ansible/clusters/my-cluster/logging/setup.yaml | grep image

echo "=== PRIAMY PATCH ==="
kubectl set image deployment/elasticsearch -n logging \
  elasticsearch=docker.elastic.co/elasticsearch/elasticsearch:8.11.0

echo "" && echo "=== GIT PUSH ==="
cd /home/ondrejko_gulkas/mon
git add ansible/clusters/my-cluster/logging/setup.yaml
git commit -m "fix: elasticsearch version 7.17.10 → 8.11.0 to match kibana"
git push origin main

echo "" && echo "=== CAKAM NA NOVY ES POD ==="
kubectl rollout status deployment/elasticsearch -n logging --timeout=120s

echo "" && echo "=== KIBANA RESTART ==="
kubectl rollout restart deployment/kibana -n logging
sleep 60

echo "" && echo "=== KIBANA TEST ==="
curl -s -o /dev/null -w "KIBANA: %{http_code}\n" http://kibana.34.89.208.249.nip.io
