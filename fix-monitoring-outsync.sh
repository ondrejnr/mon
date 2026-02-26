echo "=== CO JE OUTSYNC ==="
kubectl get application monitoring-stack -n argocd \
  -o jsonpath='{.status.sync.comparedTo}' | python3 -m json.tool 2>/dev/null
kubectl diff -f /home/ondrejko_gulkas/mon/ansible/clusters/my-cluster/monitoring/setup.yaml 2>/dev/null | grep "^[+-]" | grep -v "^---\|^+++" | head -20

echo "" && echo "=== EXPORTUJEM AKTUALNY STAV Z CLUSTRA DO GIT ==="
kubectl get ingress grafana-ingress -n monitoring -o yaml | \
  grep -A5 "ports:\|number:" | head -10

echo "" && echo "=== AKTUALNY PORT V GIT SUBORE ==="
grep -n "number:" /home/ondrejko_gulkas/mon/ansible/clusters/my-cluster/monitoring/setup.yaml

echo "" && echo "=== GIT STATUS ==="
cd /home/ondrejko_gulkas/mon && git status && git diff
