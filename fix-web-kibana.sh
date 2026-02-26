echo "=== WEB PODY ==="
kubectl get pods -n web && kubectl get pods -n web-stack

echo "" && echo "=== ARGOCD SPRAVUJE WEB? ==="
kubectl get applications -A | grep -iE "web|nginx"

echo "" && echo "=== PRIDAVAM KIBANA INGRESS ==="
kubectl apply -f - << 'KIBANA'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kibana-ingress
  namespace: logging
  annotations:
spec:
  ingressClassName: nginx
  rules:
  - host: kibana.34.89.208.249.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kibana
            port:
              number: 5601
KIBANA

echo "" && echo "=== FORCE ARGOCD SYNC WEB ==="
kubectl annotate application lamp-stack -n argocd argocd.argoproj.io/refresh=hard --overwrite 2>/dev/null
for app in $(kubectl get applications -A -o jsonpath='{.items[*].metadata.name}'); do
  kubectl annotate application $app -n argocd argocd.argoproj.io/refresh=hard --overwrite 2>/dev/null
done

echo "" && echo "=== HLADAM KTO SPRAVUJE WEB NS ==="
kubectl get kustomization -A 2>/dev/null
kubectl get helmrelease -A 2>/dev/null | grep -iE "web|nginx"

sleep 10
echo "" && echo "=== HTTP TESTY ==="
for url in web.34.89.208.249.nip.io nginx.34.89.208.249.nip.io kibana.34.89.208.249.nip.io; do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://$url)
  [[ "$code" =~ ^(200|301|302)$ ]] && icon="✅" || icon="❌"
  echo "  $icon $code → http://$url"
done
