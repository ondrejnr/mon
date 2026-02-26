echo "=== ARGOCD LOGGING STATUS ==="
kubectl get application logging-stack -n argocd \
  -o jsonpath='{.status.sync.status} {.status.health.status}' && echo ""
kubectl get application logging-stack -n argocd \
  -o jsonpath='{.status.conditions[0].message}' && echo ""

echo "" && echo "=== GIT OBSAH SETUP.YAML - ELASTICSEARCH ==="
grep -A5 "elasticsearch" \
  /home/ondrejko_gulkas/mon/ansible/clusters/my-cluster/logging/setup.yaml | head -20

echo "" && echo "=== MANUALNE APPLY ==="
kubectl apply -f /home/ondrejko_gulkas/mon/ansible/clusters/my-cluster/logging/setup.yaml

sleep 15 && echo "" && echo "=== PODY LOGGING ==="
kubectl get pods -n logging

echo "" && echo "=== KIBANA TEST ==="
curl -s -o /dev/null -w "KIBANA: %{http_code}\n" http://kibana.34.89.208.249.nip.io
