#!/bin/bash
set -euo pipefail
GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✅ $*${NC}"; }
info() { echo -e "${CYAN}ℹ️  $*${NC}"; }
step() { echo -e "\n${BOLD}═══════════════════════════════════════════${NC}"; echo -e "${BOLD}$*${NC}"; echo -e "${BOLD}═══════════════════════════════════════════${NC}"; }

step "🚀 [7/9] ARGOCD"

info "Inštalujem ArgoCD..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

info "Čakám na ArgoCD pody (120s)..."
kubectl wait --for=condition=available --timeout=120s deployment -n argocd --all 2>/dev/null || sleep 60

info "Konfigurujem argocd-server s --insecure..."
kubectl patch deployment argocd-server -n argocd --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--insecure"}]' 2>/dev/null || true
kubectl rollout restart deployment/argocd-server -n argocd
sleep 20

kubectl apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-final
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  ingressClassName: nginx
  rules:
  - host: argocd.34.89.208.249.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
YAML

for app in lamp logging monitoring web web-stack; do
  kubectl apply -f - <<APPEOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${app}-stack
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/ondrejnr/mon.git
    targetRevision: HEAD
    path: ansible/clusters/my-cluster/${app}
  destination:
    server: https://kubernetes.default.svc
    namespace: ${app}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
APPEOF
  ok "ArgoCD app: ${app}-stack"
done

sleep 10
PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "N/A")
ok "ArgoCD nasadený"
echo "  URL:  http://argocd.34.89.208.249.nip.io"
echo "  User: admin"
echo "  Pass: $PASS"
kubectl get pods -n argocd | grep -E "NAME|argocd-server"
