#!/bin/bash

# Konfigurácia
IP="34.89.208.249"
echo "🛠️ Spúšťam HLBOKÚ REKONŠTRUKCIU CLUSTERA..."

# 1. ČISTENIE ZOMBIE PROCESOV
echo "🧹 Odstraňujem nefunkčné pody a staré služby..."
kubectl delete pods -A --field-selector=status.phase!=Running --force --grace-period=0 2>/dev/null
kubectl delete svc -n ingress-nginx ingress-nginx-controller --ignore-not-found

# 2. REKONŠTRUKCIA BRÁNY (INGRESS)
echo "🌐 Nastavujem LoadBalancer na verejnú IP..."
cat <<SVC | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
spec:
  type: LoadBalancer
  externalIPs: ["$IP"]
  selector:
    app.kubernetes.io/component: controller
  ports:
    - name: http
      port: 80
      targetPort: 80
    - name: https
      port: 443
      targetPort: 443
SVC

# 3. FIX MONITORINGU (Bypass rozbitých ciest)
echo "📊 Opravujem scrapovanie Grafany a Promethea..."
# Nastavíme Grafanu natvrdo na port 3000
kubectl patch svc grafana -n monitoring --type json -p='[{"op": "replace", "path": "/spec/ports/0/port", "value": 3000},{"op": "replace", "path": "/spec/ports/0/targetPort", "value": 3000}]'
# Odstránime limity, aby pody naskočili aj pri malej RAM
kubectl patch deployment prometheus -n monitoring --type json -p='[{"op": "remove", "path": "/spec/template/spec/containers/0/resources"}]' 2>/dev/null

# 4. REKONŠTRUKCIA LAMP STACKU (Fixing ImagePullBackOff)
echo "🐘 Opravujem Apache-PHP stack (4/4 Fix)..."
kubectl delete deployment apache-php -n lamp --ignore-not-found
cat <<DEP | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: apache-php
  namespace: lamp
spec:
  replicas: 1
  selector:
    matchLabels: { app: apache-php }
  template:
    metadata:
      labels: { app: apache-php }
    spec:
      containers:
      - name: apache
        image: httpd:2.4-alpine
        ports: [{ containerPort: 80 }]
      - name: php-fpm
        image: php:8.1-fpm-alpine
        ports: [{ containerPort: 9000 }]
      - name: apache-exporter
        image: lusotycoon/apache-exporter:latest
        args: ["--scrape_uri", "http://localhost/server-status?auto"]
        ports: [{ containerPort: 9117 }]
      - name: phpfpm-exporter
        image: hipages/php-fpm_exporter:latest
        env: [{ name: PHP_FPM_SCRAPE_URI, value: "tcp://127.0.0.1:9000/status" }]
        ports: [{ containerPort: 9253 }]
DEP

# 5. GENERÁCIA INGRESS PRAVIDIEL (Domény)
echo "🛤️ Mapujem domény na opravené služby..."
for item in "bank:lamp:apache-php:80" "grafana:monitoring:grafana:3000" "prometheus:monitoring:prometheus:9090"; do
    IFS=':' read -r NAME NS TARGET PORT <<< "$item"
    cat <<ING | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${NAME}-ingress
  namespace: ${NS}
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  rules:
  - host: ${NAME}.${IP}.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ${TARGET}
            port: { number: ${PORT} }
ING
done

# 6. FINÁLNA SYNCHRONIZÁCIA
echo "🔄 Vynucujem reštart monitoringu pre vymazanie cache..."
kubectl rollout restart deployment -n monitoring
kubectl rollout restart deployment -n lamp

echo "🏁 REKONŠTRUKCIA DOKONČENÁ. Počkaj 90 sekúnd."
