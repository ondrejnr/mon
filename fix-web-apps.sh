echo "=== EXISTUJUCE ARGOCD APPS ==="
kubectl get applications -A -o custom-columns="NAME:.metadata.name,PATH:.spec.source.path,SYNC:.status.sync.status"

echo "" && echo "=== VYTVÁRAM ARGOCD APP PRE WEB ==="
kubectl apply -f - << 'APPEOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: web-stack
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/ondrejnr/mon.git
    targetRevision: HEAD
    path: ansible/clusters/my-cluster/web
  destination:
    server: https://kubernetes.default.svc
    namespace: web
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nginx-stack
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/ondrejnr/mon.git
    targetRevision: HEAD
    path: ansible/clusters/my-cluster/web-stack
  destination:
    server: https://kubernetes.default.svc
    namespace: web-stack
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
APPEOF

echo "" && echo "=== KIBANA NETWORK POLICY FIX ==="
kubectl get networkpolicy -n logging | grep -i nginx
kubectl patch networkpolicy allow-nginx-ingress-access -n logging --type=json -p='[
  {"op":"replace","path":"/spec/ingress/0/from/0","value":{"namespaceSelector":{"matchLabels":{"kubernetes.io/metadata.name":"ingress-nginx"}}}}
]' 2>/dev/null || echo "policy uz OK"

echo "" && echo "=== KIBANA INGRESS PORT CHECK ==="
kubectl get ingress kibana-ingress -n logging -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.port.number}' && echo ""
kubectl get endpoints kibana -n logging

sleep 20
echo "" && echo "=== HTTP TESTY ==="
for url in web.34.89.208.249.nip.io nginx.34.89.208.249.nip.io kibana.34.89.208.249.nip.io; do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://$url)
  [[ "$code" =~ ^(200|301|302)$ ]] && icon="✅" || icon="❌"
  echo "  $icon $code → http://$url"
done
