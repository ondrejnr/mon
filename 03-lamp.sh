#!/bin/bash
set -euo pipefail
GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✅ $*${NC}"; }
info() { echo -e "${CYAN}ℹ️  $*${NC}"; }
step() { echo -e "\n${BOLD}═══════════════════════════════════════════${NC}"; echo -e "${BOLD}$*${NC}"; echo -e "${BOLD}═══════════════════════════════════════════${NC}"; }

step "🏦 [3/9] LAMP STACK (PostgreSQL + Apache + PHP-FPM)"

kubectl apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgresql
  namespace: lamp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgresql
  template:
    metadata:
      labels:
        app: postgresql
    spec:
      containers:
      - name: postgresql
        image: postgres:15
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_DB
          value: bankdb
        - name: POSTGRES_USER
          value: bankuser
        - name: POSTGRES_PASSWORD
          value: bankpass
---
apiVersion: v1
kind: Service
metadata:
  name: postgresql
  namespace: lamp
spec:
  selector:
    app: postgresql
  ports:
  - port: 5432
    targetPort: 5432
YAML

kubectl apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: apache-php
  namespace: lamp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: apache-php
  template:
    metadata:
      labels:
        app: apache-php
    spec:
      containers:
      - name: apache
        image: php:8.2-apache
        ports:
        - containerPort: 80
      - name: phpfpm
        image: php:8.2-fpm
        ports:
        - containerPort: 9000
      - name: apache-exporter
        image: lusotycoon/apache-exporter:latest
        ports:
        - containerPort: 9117
        args:
        - --scrape_uri=http://localhost/server-status?auto
      - name: phpfpm-exporter
        image: hipages/php-fpm_exporter:2
        ports:
        - containerPort: 9253
        env:
        - name: PHP_FPM_SCRAPE_URI
          value: tcp://localhost:9000/status
---
apiVersion: v1
kind: Service
metadata:
  name: apache-php
  namespace: lamp
spec:
  selector:
    app: apache-php
  ports:
  - name: http
    port: 80
    targetPort: 80
  - name: apache-exporter
    port: 9117
    targetPort: 9117
  - name: phpfpm-exporter
    port: 9253
    targetPort: 9253
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: apache-ingress
  namespace: lamp
spec:
  ingressClassName: nginx
  rules:
  - host: bank.34.89.208.249.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: apache-php
            port:
              number: 80
YAML

info "Čakám na LAMP pody (60s)..."
sleep 30
kubectl wait --for=condition=ready pod -l app=apache-php -n lamp --timeout=60s 2>/dev/null || true
kubectl wait --for=condition=ready pod -l app=postgresql -n lamp --timeout=60s 2>/dev/null || true

POD=$(kubectl get pods -n lamp -l app=apache-php -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "$POD" ]; then
  kubectl exec -n lamp $POD -c apache -- sh -c \
    'test -f /var/www/html/index.php || echo "<?php echo \"<h1>Bank App</h1>\"; phpinfo(); ?>" > /var/www/html/index.php' 2>/dev/null || true
  ok "index.php vytvorený"
fi

ok "LAMP stack nasadený"
kubectl get pods -n lamp
