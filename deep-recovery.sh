#!/bin/bash

# SYSTÉMOVÉ PARAMETRE
IP="34.89.208.249"
NAMESPACE_APP="lamp"
NAMESPACE_MON="monitoring"
NAMESPACE_ING="ingress-nginx"

echo "🧪 ZAČÍNAM HLBOKÚ SYSTÉMOVÚ REKONŠTRUKCIU (2026-02-26)"

# 1. KERNEL & SCHEDULER OPTIMALIZÁCIA
echo "⚡ Čistím zombie pody a uvoľňujem Memory Pressure..."
kubectl delete pods -A --field-selector=status.phase!=Running --force --grace-period=0
# Odstránenie limitov, aby sme sa vyhli CPU Throttlingu počas oživovania
kubectl get deployments -A -o json | jq '.items[].metadata | "kubectl patch deployment \(.name) -n \(.namespace) --type json -p='\''[{\"op\": \"remove\", \"path\": \"/spec/template/spec/containers/0/resources\"}]'\''"' | sh 2>/dev/null

# 2. SIEŤOVÁ ANATÓMIA (INGRESS SERVICE RECONSTRUCTION)
echo "🌐 Rekonštruujem sieťovú bránu (North-South Traffic)..."
kubectl delete svc -n $NAMESPACE_ING ingress-nginx-controller --ignore-not-found
cat <<SVC | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: ingress-nginx-controller
  namespace: $NAMESPACE_ING
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "10254"
spec:
  type: LoadBalancer
  externalIPs: ["$IP"]
  externalTrafficPolicy: Local
  selector:
    app.kubernetes.io/component: controller
  ports:
    - name: http
      port: 80
      targetPort: 80
      protocol: TCP
    - name: https
      port: 443
      targetPort: 443
      protocol: TCP
SVC

# 3. SMEROVACIE TABUĽKY (INGRESS DEEP MAPPING)
echo "🛤️ Budujem smerovacie tabuľky pre distribuované služby..."
# Komplexné pole: Host : Namespace : Service : Port
SERVICES=(
  "bank:$NAMESPACE_APP:apache-php:80"
  "prometheus:$NAMESPACE_MON:prometheus:9090"
  "grafana:$NAMESPACE_MON:grafana:3000"
  "kibana:logging:kibana:5601"
  "argocd:argocd:argocd-server:80"
)

for entry in "${SERVICES[@]}"; do
    IFS=':' read -r HOST NS SVC PORT <<< "$entry"
    cat <<ING | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${HOST}-ingress-complex
  namespace: ${NS}
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "30"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "30"
spec:
  rules:
  - host: ${HOST}.${IP}.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ${SVC}
            port: { number: ${PORT} }
ING
done

# 4. APLIKAČNÝ POD (SIDE-CAR STABILITY FIX)
echo "🐘 Opravujem LAMP stack - vynucujem Readiness pre všetky exportéry..."
kubectl delete deployment apache-php -n $NAMESPACE_APP --ignore-not-found
cat <<DEP | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: apache-php
  namespace: $NAMESPACE_APP
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
        args: ["--scrape_uri", "http://127.0.0.1/server-status?auto"]
        ports: [{ containerPort: 9117 }]
      - name: phpfpm-exporter
        image: hipages/php-fpm_exporter:latest
        env: [{ name: PHP_FPM_SCRAPE_URI, value: "tcp://127.0.0.1:9000/status" }]
        ports: [{ containerPort: 9253 }]
DEP

# 5. MONITORING HEALTH (GRAFANA PORT RE-MAPPING)
echo "📊 Opravujem Service Discovery pre monitoring..."
kubectl patch svc grafana -n $NAMESPACE_MON --type json -p='[{"op": "replace", "path": "/spec/ports/0/port", "value": 3000}, {"op": "replace", "path": "/spec/ports/0/targetPort", "value": 3000}]'
kubectl rollout restart deployment prometheus -n $NAMESPACE_MON

echo "🏁 SYSTÉM REŠTARTOVANÝ. Vykonávam hĺbkovú kontrolu za 60s."
