#!/bin/bash
set -euo pipefail
GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✅ $*${NC}"; }
info() { echo -e "${CYAN}ℹ️  $*${NC}"; }
step() { echo -e "\n${BOLD}═══════════════════════════════════════════${NC}"; echo -e "${BOLD}$*${NC}"; echo -e "${BOLD}═══════════════════════════════════════════${NC}"; }

step "🌍 [6/9] WEB STACK (Nginx v web + web-stack)"

kubectl apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx
  namespace: web
spec:
  selector:
    app: nginx
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-ingress
  namespace: web
spec:
  ingressClassName: nginx
  rules:
  - host: web.34.89.208.249.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nginx
            port:
              number: 80
YAML

kubectl apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: web-stack
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx
  namespace: web-stack
spec:
  selector:
    app: nginx
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-ingress
  namespace: web-stack
spec:
  ingressClassName: nginx
  rules:
  - host: nginx.34.89.208.249.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nginx
            port:
              number: 80
YAML

info "Čakám na web pody (30s)..."
sleep 15
kubectl wait --for=condition=ready pod -l app=nginx -n web --timeout=30s 2>/dev/null || true
kubectl wait --for=condition=ready pod -l app=nginx -n web-stack --timeout=30s 2>/dev/null || true

ok "Web stack nasadený"
kubectl get pods -n web && kubectl get pods -n web-stack
