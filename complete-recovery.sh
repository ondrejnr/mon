#!/bin/bash
set -euo pipefail

echo "══════════════════════════════════════════════════════════════════════════"
echo "🔥 ÚPLNÁ OBNOVA KLASTRA DO AKTUÁLNEHO FUNKČNÉHO STAVU"
echo "══════════════════════════════════════════════════════════════════════════"

cd /home/ondrejko_gulkas/mon/recovery-steps

# ----------------------------------------------------------------------
# 1. INGRESS CONTROLLER
# ----------------------------------------------------------------------
echo -e "\n📦 [1/9] Inštalácia Ingress controller"
./01-setup-ingress.sh

# ----------------------------------------------------------------------
# 2. OPRAVA LOCAL-PATH-PROVISIONERA (pre správne PVC)
# ----------------------------------------------------------------------
echo -e "\n🛠️ [2/9] Oprava local-path-provisioner"
kubectl patch configmap local-path-config -n kube-system --type=merge -p='{
  "data": {
    "config.json": "{\"nodePathMap\":[{\"node\":\"DEFAULT_PATH_FOR_NON_LISTED_NODES\",\"paths\":[\"/opt/local-path-provisioner\"]}]}"
  }
}' 2>/dev/null || true
kubectl rollout restart deployment/local-path-provisioner -n kube-system
sleep 10

# ----------------------------------------------------------------------
# 3. LOGGING STACK (Elasticsearch, Kibana, Vector)
# ----------------------------------------------------------------------
echo -e "\n📊 [3/9] Nasadenie logging stacku"
./02-setup-logging.sh

# ----------------------------------------------------------------------
# 4. MONITORING STACK (Prometheus, Grafana, Alertmanager)
# ----------------------------------------------------------------------
echo -e "\n📈 [4/9] Nasadenie monitoringu"
./04-setup-monitoring.sh

# Pridanie NetworkPolicy pre Grafana (ak nie je)
kubectl apply -f - <<NP 2>/dev/null || true
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus-to-grafana
  namespace: monitoring
spec:
  podSelector:
    matchLabels:
      app: grafana
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: prometheus
    ports:
    - port: 3000
NP

# ----------------------------------------------------------------------
# 5. LAMP (Banka)
# ----------------------------------------------------------------------
echo -e "\n🏦 [5/9] Nasadenie banky (lamp)"
./03-setup-lamp.sh
./03-fix-lamp.sh   # aplikácia fixov pre Apache a PHP

# ----------------------------------------------------------------------
# 6. WEB A WEB-STACK (jednoduché nginx)
# ----------------------------------------------------------------------
echo -e "\n🌐 [6/9] Nasadenie webov"
./05-setup-web.sh

# ----------------------------------------------------------------------
# 7. ARGOCD
# ----------------------------------------------------------------------
echo -e "\n🚀 [7/9] Nasadenie ArgoCD"
./06-setup-argocd.sh

# Pridanie ArgoCD aplikácií pre existujúce namespace
for app in lamp monitoring logging web web-stack; do
  kubectl apply -f - <<APP 2>/dev/null || true
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $app-stack
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/ondrejnr/mon.git
    targetRevision: main
    path: ansible/clusters/my-cluster/$app
  destination:
    server: https://kubernetes.default.svc
    namespace: $app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
APP
done

# ----------------------------------------------------------------------
# 8. ONLINE-RETAIL (CloudNativePG, Redis, frontend, product-service)
# ----------------------------------------------------------------------
echo -e "\n🛒 [8/9] Nasadenie online-retail"

# Namespace
kubectl create namespace online-retail --dry-run=client -o yaml | kubectl apply -f -

# Secret pre PostgreSQL
kubectl apply -n online-retail -f - <<SECRET
apiVersion: v1
kind: Secret
metadata:
  name: postgres-secret
type: kubernetes.io/basic-auth
stringData:
  username: app
  password: password
SECRET

kubectl apply -n online-retail -f - <<SECRET2
apiVersion: v1
kind: Secret
metadata:
  name: postgres-app-secret
type: kubernetes.io/basic-auth
stringData:
  username: app
  password: password
SECRET2

# CloudNativePG operátor (Helm)
helm repo add cnpg https://cloudnative-pg.io/charts/ 2>/dev/null || true
helm repo update
helm upgrade --install cnpg cnpg/cloudnative-pg \
  --namespace online-retail \
  --wait \
  --timeout 5m \
  --create-namespace

# PostgreSQL cluster
cat <<CLUSTER | kubectl apply -f -
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres
  namespace: online-retail
spec:
  instances: 1
  storage:
    size: 1Gi
    storageClass: local-path
  bootstrap:
    initdb:
      database: products
      owner: app
      secret:
        name: postgres-app-secret
CLUSTER

# Redis (Helm)
helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
helm upgrade --install redis bitnami/redis \
  --namespace online-retail \
  --set architecture=standalone \
  --wait \
  --timeout 5m

# RabbitMQ (voliteľné, ak treba)
helm upgrade --install rabbitmq bitnami/rabbitmq \
  --namespace online-retail \
  --set auth.username=guest,auth.password=guest \
  --wait \
  --timeout 5m || true

# Frontend
cat <<FRONTEND | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: online-retail
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "80"
    spec:
      imagePullSecrets:
      - name: regcred
      containers:
      - name: frontend
        image: ondrejnr1/frontend:latest
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: frontend
  namespace: online-retail
spec:
  selector:
    app: frontend
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: frontend
  namespace: online-retail
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: shop.34.89.208.249.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend
            port:
              number: 80
FRONTEND

# Product-service
cat <<PRODUCT | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: product-service
  namespace: online-retail
spec:
  replicas: 2
  selector:
    matchLabels:
      app: product-service
  template:
    metadata:
      labels:
        app: product-service
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
    spec:
      imagePullSecrets:
      - name: regcred
      containers:
      - name: product-service
        image: ondrejnr1/product-service:latest
        ports:
        - containerPort: 8080
        env:
        - name: DB_HOST
          value: postgres-rw
        - name: DB_PORT
          value: "5432"
        - name: DB_NAME
          value: "products"
        - name: DB_USER
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: username
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: password
---
apiVersion: v1
kind: Service
metadata:
  name: product-service
  namespace: online-retail
spec:
  selector:
    app: product-service
  ports:
  - port: 8080
    targetPort: 8080
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: product-service
  namespace: online-retail
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: api.34.89.208.249.nip.io
    http:
      paths:
      - path: /products
        pathType: Prefix
        backend:
          service:
            name: product-service
            port:
              number: 8080
PRODUCT

# ArgoCD aplikácia pre online-retail
kubectl apply -f - <<APP
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: online-retail
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/ondrejnr/mon.git
    targetRevision: main
    path: online-retail
  destination:
    server: https://kubernetes.default.svc
    namespace: online-retail
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
APP

# ----------------------------------------------------------------------
# 9. ZÁVEREČNÉ ÚPRAVY (index pattern v Kibane, atď.)
# ----------------------------------------------------------------------
echo -e "\n🎨 [9/9] Záverečné úpravy"

# Počkáme na Elasticsearch
sleep 20

# Vytvorenie index pattern v Kibane
KIBANA_URL="http://kibana.34.89.208.249.nip.io"
curl -s -X POST "$KIBANA_URL/api/saved_objects/index-pattern" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d '{"attributes":{"title":"logs-lamp-*","timeFieldName":"@timestamp"}}' 2>/dev/null || true

curl -s -X POST "$KIBANA_URL/api/saved_objects/index-pattern" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d '{"attributes":{"title":"logs-retail-*","timeFieldName":"@timestamp"}}' 2>/dev/null || true

echo -e "\n✅ Obnova dokončená! Všetky služby by mali byť funkčné."
echo "   Frontend: http://shop.34.89.208.249.nip.io"
echo "   API: http://api.34.89.208.249.nip.io/products"
echo "   Banka: http://bank.34.89.208.249.nip.io"
echo "   ArgoCD: http://argocd.34.89.208.249.nip.io"
echo "   Grafana: http://grafana.34.89.208.249.nip.io"
echo "   Kibana: http://kibana.34.89.208.249.nip.io"
