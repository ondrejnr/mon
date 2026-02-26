#!/bin/bash
set -e
echo "=== [3/7] Banka (lamp) ==="
kubectl create namespace lamp 2>/dev/null || true
# PostgreSQL
cat << 'POST' | kubectl apply -f -
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
POST
# Apache-php
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
sleep 10
# Vytvorenie index.php
POD=$(kubectl get pods -n lamp -l app=apache-php -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$POD" ]; then
    kubectl exec -n lamp $POD -c apache -- sh -c "echo '<?php phpinfo(); ?>' > /usr/local/apache2/htdocs/index.php"
    echo "✅ index.php vytvorený"
fi
echo "✅ Banka nasadená."
