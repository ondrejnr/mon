#!/bin/bash
set -euo pipefail
echo "══════════════════════════════════════════════════════════════════════════"
echo "🚀 FINÁLNA OBNOVA – BANKA, ARGOCD, PROMETHEUS, GRAFANA"
echo "══════════════════════════════════════════════════════════════════════════"

# Farby pre výstup
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

# ----------------------------------------------------------------------
# 1. OBNOVA BANKY (deployment apache-php)
# ----------------------------------------------------------------------
echo -e "\n${YELLOW}🏦 [1/6] Obnova deploymentu banky${NC}"
NAMESPACE_LAMP="lamp"

if ! kubectl get deployment apache-php -n $NAMESPACE_LAMP &>/dev/null; then
    echo "Deployment apache-php neexistuje, vytváram ho z manifestu..."
    kubectl apply -f /home/ondrejko_gulkas/mon/recovery-steps/03-setup-lamp.sh 2>/dev/null || {
        echo "❌ Chyba pri aplikovaní 03-setup-lamp.sh, skúšam priamo..."
        cat << 'DEPLOY' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: apache-php
  namespace: $NAMESPACE_LAMP
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
  namespace: $NAMESPACE_LAMP
spec:
  selector:
    app: apache-php
  ports:
  - port: 80
    targetPort: 80
    name: http
DEPLOY
    }
    echo "⏳ Čakám na pod..."
    sleep 20
else
    echo "✅ Deployment apache-php už existuje."
fi

# Počkáme, kým je pod v stave Running
POD=$(kubectl get pods -n $NAMESPACE_LAMP -l app=apache-php -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$POD" ]; then
    echo "❌ Pod banky sa nespustil!"
    exit 1
fi
echo -e "${GREEN}✅ Bank pod: $POD${NC}"

# ----------------------------------------------------------------------
# 2. APACHE KONFIGURÁCIA (prepojenie s PHP-FPM)
# ----------------------------------------------------------------------
echo -e "\n${YELLOW}🔧 [2/6] Aplikácia Apache konfigurácie (proxy_fcgi)${NC}"

# ConfigMap
kubectl delete configmap apache-php-config -n $NAMESPACE_LAMP --ignore-not-found
cat << 'CONF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: apache-php-config
  namespace: $NAMESPACE_LAMP
data:
  httpd.conf: |
    ServerName localhost
    LoadModule mpm_event_module modules/mod_mpm_event.so
    LoadModule unixd_module modules/mod_unixd.so
    LoadModule authz_core_module modules/mod_authz_core.so
    LoadModule dir_module modules/mod_dir.so
    LoadModule env_module modules/mod_env.so
    LoadModule log_config_module modules/mod_log_config.so
    LoadModule mime_module modules/mod_mime.so
    LoadModule alias_module modules/mod_alias.so
    LoadModule proxy_module modules/mod_proxy.so
    LoadModule proxy_fcgi_module modules/mod_proxy_fcgi.so
    User daemon
    Group daemon
    ServerAdmin admin@localhost
    ErrorLog /proc/self/fd/2
    LogLevel warn
    <IfModule log_config_module>
        LogFormat "%h %l %u %t \"%r\" %>s %b" common
        CustomLog /proc/self/fd/1 common
    </IfModule>
    DocumentRoot /usr/local/apache2/htdocs
    <Directory /usr/local/apache2/htdocs>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    <FilesMatch \.php$>
        SetHandler proxy:fcgi://127.0.0.1:9000
    </FilesMatch>
CONF

# Patch deploymentu
kubectl patch deployment apache-php -n $NAMESPACE_LAMP --type='json' -p='[
  {"op":"add","path":"/spec/template/spec/volumes/-","value":{"name":"apache-config","configMap":{"name":"apache-php-config"}}},
  {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{"name":"apache-config","mountPath":"/usr/local/apache2/conf/httpd.conf","subPath":"httpd.conf"}}
]' 2>/dev/null || echo "ConfigMap už je pripojená."

kubectl rollout restart deployment/apache-php -n $NAMESPACE_LAMP
sleep 15

# ----------------------------------------------------------------------
# 3. ARGOCD – DOČISTENIE CRD
# ----------------------------------------------------------------------
echo -e "\n${YELLOW}🚀 [3/6] Vyčistenie ArgoCD CRD${NC}"
for crd in applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io; do
    echo "Odstraňujem $crd..."
    kubectl delete crd $crd --ignore-not-found --force --grace-period=0 2>/dev/null || true
    # Počkáme, kým zmizne
    while kubectl get crd $crd &>/dev/null; do
        echo "   Čakám na zmazanie $crd..."
        sleep 2
    done
done

# Reinštalácia ArgoCD (bez CRD, tie sa vytvoria znova)
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
sleep 30

# Pridanie --insecure do argocd-server
kubectl patch deployment argocd-server -n argocd --type='json' -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--insecure"}]' 2>/dev/null || true

# Ingress (pre istotu znova)
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

kubectl rollout restart deployment/argocd-server -n argocd
sleep 15

# ----------------------------------------------------------------------
# 4. PROMETHEUS – ANOTÁCIE A KONTROLA
# ----------------------------------------------------------------------
echo -e "\n${YELLOW}📈 [4/6] Nastavenie Prometheus anotácií${NC}"
# Pre banku
kubectl annotate pod -n lamp -l app=apache-php prometheus.io/scrape=true --overwrite 2>/dev/null || true
kubectl annotate pod -n lamp -l app=apache-php prometheus.io/port=9117 --overwrite 2>/dev/null || true

# Pre monitoring komponenty (už by mali byť)
for ns in monitoring web web-stack; do
    for pod in $(kubectl get pods -n $ns -o name | cut -d/ -f2); do
        kubectl annotate pod -n $ns $pod prometheus.io/scrape=true --overwrite 2>/dev/null || true
    done
done

kubectl rollout restart deployment/prometheus -n monitoring
sleep 15

# ----------------------------------------------------------------------
# 5. GRAFANA – DATASOURCE (overenie)
# ----------------------------------------------------------------------
echo -e "\n${YELLOW}📊 [5/6] Kontrola Grafana datasource${NC}"
GRAFANA_POD=$(kubectl get pods -n monitoring -l app=grafana -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$GRAFANA_POD" ]; then
    kubectl exec -n monitoring $GRAFANA_POD -- sh -c "mkdir -p /etc/grafana/provisioning/datasources"
    cat << 'DS' | kubectl exec -n monitoring -i $GRAFANA_POD -- sh -c "cat > /etc/grafana/provisioning/datasources/datasources.yaml"
apiVersion: 1
datasources:
- name: Prometheus
  type: prometheus
  access: proxy
  url: http://prometheus.monitoring:9090
  isDefault: true
DS
    kubectl rollout restart deployment/grafana -n monitoring
    echo "✅ Datasource pridaný, Grafana reštartovaná."
else
    echo "❌ Grafana pod neexistuje."
fi
sleep 20

# ----------------------------------------------------------------------
# 6. ZÁVEREČNÝ TEST
# ----------------------------------------------------------------------
echo -e "\n${YELLOW}🌐 [6/6] Testovanie všetkých webov${NC}"
WEBS=(
    bank.34.89.208.249.nip.io
    argocd.34.89.208.249.nip.io
    grafana.34.89.208.249.nip.io
    alertmanager.34.89.208.249.nip.io
    kibana.34.89.208.249.nip.io
    prometheus.34.89.208.249.nip.io
    web.34.89.208.249.nip.io
    nginx.34.89.208.249.nip.io
)
for url in "${WEBS[@]}"; do
    echo -n "http://$url ... "
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 http://$url || echo "timeout")
    if [[ "$code" =~ ^(200|301|302|401|403)$ ]]; then
        echo -e "${GREEN}$code${NC}"
    else
        echo -e "${RED}$code${NC}"
    fi
done

echo -e "\n${GREEN}══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ OBNOVA DOKONČENÁ${NC}"
echo -e "${GREEN}Počkajte 5 minút a potom skontrolujte Prometheus targets a Grafana dáta.${NC}"
echo -e "${GREEN}Ak všetko prebehlo dobre, commitnite stav do Gitu:${NC}"
echo "cd /home/ondrejko_gulkas/mon && git add . && git commit -m 'fix: final working state after recovery' && git push origin main"
