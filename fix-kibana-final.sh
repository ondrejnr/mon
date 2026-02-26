echo "=== KIBANA NETWORK POLICY ==="
kubectl get networkpolicy -n logging -o yaml | grep -A15 "ingress:"

echo "" && echo "=== TEST PRIAMO Z INGRESS NA KIBANA ==="
kubectl exec -n ingress-nginx deployment/ingress-nginx-controller -- \
  curl -s -o /dev/null -w "%{http_code}" http://10.42.0.232:5601

echo "" && echo "=== MAZEM A RECREATE NETWORK POLICY ==="
kubectl delete networkpolicy allow-nginx-ingress-access -n logging
kubectl apply -f - << 'NP'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-nginx-ingress-access
  namespace: logging
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ingress-nginx
  - from:
    - podSelector: {}
NP

sleep 5
curl -s -o /dev/null -w "KIBANA: %{http_code}\n" http://kibana.34.89.208.249.nip.io
