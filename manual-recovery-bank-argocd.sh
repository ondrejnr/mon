#!/bin/bash
set -e
echo "═══════════════════════════════════════════════════════════════"
echo "🛠️ MANUÁLNA OBNOVA BANKY A ARGOCD (ČISTÉ MANIFESTY)"
echo "═══════════════════════════════════════════════════════════════"

# 1. Obnova LAMP (banka)
echo ""
echo "📦 [1/4] NASADZUJEM BANKU (PostgreSQL + Apache-PHP)"
kubectl create namespace lamp 2>/dev/null || true

# PostgreSQL
cat << 'POSTGRES' | kubectl apply -f -
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
        env:
        - name: POSTGRES_PASSWORD
          value: "password"
        - name: POSTGRES_DB
          value: "bank"
        ports:
        - containerPort: 5432
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
POSTGRES

# Apache-PHP (správny image pre phpfpm-exporter)
cat << 'APACHE' | kubectl apply -f -
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
        image: httpd:alpine
        ports:
        - containerPort: 80
        volumeMounts:
        - name: www
          mountPath: /usr/local/apache2/htdocs
      - name: phpfpm
        image: php:fpm-alpine
        ports:
        - containerPort: 9000
        volumeMounts:
        - name: www
          mountPath: /var/www/html
      - name: apache-exporter
        image: bitnami/apache-exporter:latest
        ports:
        - containerPort: 9117
      - name: phpfpm-exporter
        image: hipages/php-fpm_exporter:2
        ports:
        - containerPort: 9253
        args: ["--phpfpm.scrape-uri", "tcp://127.0.0.1:9000/status"]
      volumes:
      - name: www
        emptyDir: {}
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
  - port: 80
    targetPort: 80
    name: http
  - port: 9117
    targetPort: 9117
    name: apache-exporter
  - port: 9253
    targetPort: 9253
    name: phpfpm-exporter
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: bank-final
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
APACHE

# 2. Vytvorenie jednoduchého index.php (ak pod vznikne)
sleep 5
BANK_POD=$(kubectl get pods -n lamp -l app=apache-php -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$BANK_POD" ]; then
  kubectl exec -n lamp $BANK_POD -c apache -- sh -c "echo '<?php phpinfo(); ?>' > /var/www/html/index.php"
fi

# 3. Obnova ArgoCD
echo ""
echo "🚀 [2/4] INŠTALUJEM ARGOCD Z OFICIÁLNEHO MANIFESTU"
kubectl create namespace argocd 2>/dev/null || true
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Počkám na základné pody (najmä argocd-server)
echo "⏳ Čakám na spustenie ArgoCD..."
sleep 45

# Pridanie --insecure do argocd-server
kubectl patch deployment argocd-server -n argocd --type='json' -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--insecure"}]'

# Vytvorenie Ingress pre ArgoCD
cat << 'INGRESS' | kubectl apply -f -
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
INGRESS

# 4. Overenie a test
echo ""
echo "🔍 [3/4] KONTROLA PODOV"
kubectl get pods -n lamp
kubectl get pods -n argocd

echo ""
echo "🌐 [4/4] TESTOVANIE VŠETKÝCH WEBOV"
for url in bank.34.89.208.249.nip.io argocd.34.89.208.249.nip.io grafana.34.89.208.249.nip.io alertmanager.34.89.208.249.nip.io kibana.34.89.208.249.nip.io prometheus.34.89.208.249.nip.io nginx.34.89.208.249.nip.io web.34.89.208.249.nip.io; do
  echo -n "http://$url ... "
  curl -s -o /dev/null -w "%{http_code}\n" --max-time 5 http://$url
done

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ OBNOVA DOKONČENÁ"
echo "═══════════════════════════════════════════════════════════════"
