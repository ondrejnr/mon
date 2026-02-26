echo "=== KIBANA INGRESS DETAIL ==="
kubectl get ingress -n logging -o yaml | grep -A20 "rules:"

echo "" && echo "=== KIBANA SERVICE PORT ==="
kubectl get svc kibana -n logging -o jsonpath='{.spec.ports[*].port}' && echo ""

echo "" && echo "=== KIBANA ENDPOINT ==="
kubectl get endpoints kibana -n logging

echo "" && echo "=== NGINX WEB - HLADAM VO VSETKYCH NS ==="
kubectl get all -n web 2>/dev/null
kubectl get all -n web-stack 2>/dev/null
kubectl get ingress -A | grep -v "argocd\|lamp\|monitoring\|logging\|flux"

echo "" && echo "=== GIT - WEB MANIFESTY ==="
cat /home/ondrejko_gulkas/mon/ansible/clusters/my-cluster/web/setup.yaml 2>/dev/null
cat /home/ondrejko_gulkas/mon/ansible/clusters/my-cluster/web-stack/setup.yaml 2>/dev/null
