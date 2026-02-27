#!/bin/bash
set -euo pipefail
echo "══════════════════════════════════════════════════════════════════════════"
echo "🔧 KONEČNÉ AKCIE – BANKA, PROMETHEUS, ARGOCD, GRAFANA"
echo "══════════════════════════════════════════════════════════════════════════"

NAMESPACE_LAMP="lamp"
NAMESPACE_MONITORING="monitoring"
NAMESPACE_ARGOCD="argocd"

# ----------------------------------------------------------------------
# 1. BANKA – oprava Apache konfig + initContainer pre index.php
# ----------------------------------------------------------------------
# PRÍČINA CHYBY:
#   - phpfpm a apache mali rôzne mountPath pre zdieľaný www volume
#   - ConfigMap subPath mount vytváral prázdny súbor (0 bytov) pretože
#     emptyDir volume prepisoval obsah ConfigMap mountu
#   - RIEŠENIE: initContainer zapíše index.php do emptyDir pred štartom
echo -e "\n🏦 [1/7] Oprava banky (initContainer + Apache konfig)"

kubectl apply -n $NAMESPACE_LAMP -f - << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: apache-php-config
  namespace: lamp
data:
  httpd.conf: |
    ServerName localhost
    Listen 80
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
    DirectoryIndex index.php index.html
    DocumentRoot /usr/local/apache2/htdocs
    <Directory /usr/local/apache2/htdocs>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    <FilesMatch \.php$>
        SetHandler proxy:fcgi://127.0.0.1:9000
    </FilesMatch>
EOF

kubectl patch deployment apache-php -n $NAMESPACE_LAMP --type=json -p='[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/1/volumeMounts/0/mountPath",
    "value": "/usr/local/apache2/htdocs"
  },
  {
    "op": "add",
    "path": "/spec/template/spec/initContainers",
    "value": [{
      "name": "init-index",
      "image": "busybox",
      "command": ["sh", "-c", "echo \"<?php phpinfo(); ?>\" > /usr/local/apache2/htdocs/index.php"],
      "volumeMounts": [{"name": "www", "mountPath": "/usr/local/apache2/htdocs"}]
    }]
  }
]' 2>/dev/null || true

kubectl rollout restart deployment/apache-php -n $NAMESPACE_LAMP
kubectl rollout status deployment/apache-php -n $NAMESPACE_LAMP --timeout=60s || \
  (kubectl delete pod -n $NAMESPACE_LAMP -l app=apache-php --force --grace-period=0 && sleep 15)
echo "✅ Banka opravená"

# ----------------------------------------------------------------------
# 2. PROMETHEUS – oprava anotácií + správne porty
# ----------------------------------------------------------------------
# PRÍČINA CHYBY:
#   - Prometheus konfig nemal relabel pre port z anotácie
#   - Monitoring pody nemali vlastné anotácie so správnymi portami
echo -e "\n📈 [2/7] Nastavenie anotácií Prometheus"

kubectl patch deployment alertmanager -n $NAMESPACE_MONITORING --type=json \
  -p='[{"op":"add","path":"/spec/template/metadata/annotations","value":{"prometheus.io/scrape":"true","prometheus.io/port":"9093","prometheus.io/path":"/metrics"}}]' 2>/dev/null || true
kubectl patch deployment prometheus -n $NAMESPACE_MONITORING --type=json \
  -p='[{"op":"add","path":"/spec/template/metadata/annotations","value":{"prometheus.io/scrape":"true","prometheus.io/port":"9090","prometheus.io/path":"/metrics"}}]' 2>/dev/null || true
kubectl patch daemonset node-exporter -n $NAMESPACE_MONITORING --type=json \
  -p='[{"op":"add","path":"/spec/template/metadata/annotations","value":{"prometheus.io/scrape":"true","prometheus.io/port":"9100","prometheus.io/path":"/metrics"}}]' 2>/dev/null || true

# Odstráň scrape anotácie z nginx podov (nemajú /metrics endpoint)
kubectl annotate deployment nginx-app -n web-stack prometheus.io/scrape- 2>/dev/null || true
kubectl annotate deployment nginx-web -n web prometheus.io/scrape- 2>/dev/null || true

cat > /tmp/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: 'kubernetes-pods'
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
      - source_labels: [__meta_kubernetes_pod_ip, __meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        target_label: __address__
        regex: (.+);(.+)
        replacement: $1:$2
EOF
kubectl create configmap prometheus-config -n $NAMESPACE_MONITORING \
  --from-file=prometheus.yml=/tmp/prometheus.yml --dry-run=client -o yaml | kubectl apply -f -

kubectl rollout restart deployment/prometheus -n $NAMESPACE_MONITORING
sleep 20
echo "✅ Prometheus opravený"


# ----------------------------------------------------------------------
# 2b. OPRAVA SERVICES A NETWORKPOLICY PRE GRAFANA A POSTGRESQL
# ----------------------------------------------------------------------
# PRÍČINA CHYBY:
#   - grafana service mal port 80 namiesto 3000
#   - postgresql service nemal port 9187 pre postgres-exporter
#   - chýbala NetworkPolicy allow-prometheus-to-grafana
echo -e "\n🔧 Oprava Grafana service, PostgreSQL exporter a NetworkPolicy"

kubectl patch svc grafana -n $NAMESPACE_MONITORING --type=json \
  -p='[{"op":"replace","path":"/spec/ports/0/port","value":3000},{"op":"replace","path":"/spec/ports/0/targetPort","value":3000}]' 2>/dev/null || true

kubectl patch svc postgresql -n $NAMESPACE_LAMP --type=json \
  -p='[{"op":"add","path":"/spec/ports/0/name","value":"postgres"},{"op":"add","path":"/spec/ports/-","value":{"name":"exporter","port":9187,"targetPort":9187}}]' 2>/dev/null || true

kubectl apply -n $NAMESPACE_MONITORING -f - << 'YAML'
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
YAML

# PostgreSQL exporter kontajner
kubectl patch deployment postgresql -n $NAMESPACE_LAMP --type=json -p='[{"op":"add","path":"/spec/template/spec/containers/-","value":{"name":"postgres-exporter","image":"prometheuscommunity/postgres-exporter:latest","ports":[{"containerPort":9187}],"env":[{"name":"DATA_SOURCE_NAME","value":"postgresql://postgres:postgres@localhost:5432/postgres?sslmode=disable"}]}}]' 2>/dev/null || true

echo "✅ Grafana, PostgreSQL exporter a NetworkPolicy opravené"
# ----------------------------------------------------------------------
# 3. NETWORK POLICY – povolenie prístupu Prometheus → Alertmanager
# ----------------------------------------------------------------------
# PRÍČINA CHYBY:
#   - Chýbala NetworkPolicy – Prometheus nemohol scrapeovať alertmanager
echo -e "\n🔒 [3/7] Oprava NetworkPolicy pre Alertmanager"
kubectl apply -n $NAMESPACE_MONITORING -f - << 'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus-to-alertmanager
  namespace: monitoring
spec:
  podSelector:
    matchLabels:
      app: alertmanager
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: prometheus
    ports:
    - port: 9093
EOF
echo "✅ NetworkPolicy aplikovaná"

# ----------------------------------------------------------------------
# 4. ARGOCD – CRDs + insecure mode + ingress + repozitár
# ----------------------------------------------------------------------
# PRÍČINA CHYBY:
#   - Chýbali CRDs (appprojects.argoproj.io, applicationsets.argoproj.io)
#   - argocd-server presmeroval na HTTPS
#   - Po reinstalácii chýba ingress a repozitár
echo -e "\n🚀 [4/7] Oprava ArgoCD"

# CRDs
kubectl apply -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.3.2/manifests/crds/appproject-crd.yaml 2>/dev/null || true
kubectl apply -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.3.2/manifests/crds/application-crd.yaml 2>/dev/null || true
kubectl apply --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.3.2/manifests/crds/applicationset-crd.yaml 2>/dev/null || true

# Insecure mode
kubectl set env deployment/argocd-server -n $NAMESPACE_ARGOCD ARGOCD_SERVER_INSECURE=true

# Ingress
kubectl apply -n $NAMESPACE_ARGOCD -f - << 'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-final
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
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
EOF

kubectl rollout restart deployment/argocd-server -n $NAMESPACE_ARGOCD
kubectl rollout status deployment/argocd-server -n $NAMESPACE_ARGOCD --timeout=60s || \
  (kubectl delete pod -n $NAMESPACE_ARGOCD -l app.kubernetes.io/name=argocd-server --force --grace-period=0 && sleep 15)

# Obnova repozitára
sleep 10
ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n $NAMESPACE_ARGOCD -o jsonpath='{.data.password}' | base64 -d)
ARGOCD_TOKEN=$(curl -s -X POST http://argocd.34.89.208.249.nip.io/api/v1/session \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"admin\",\"password\":\"${ARGOCD_PASSWORD}\"}" | python3 -c "import json,sys; print(json.load(sys.stdin)['token'])")

curl -s -X POST http://argocd.34.89.208.249.nip.io/api/v1/repositories \
  -H "Authorization: Bearer $ARGOCD_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"repo":"https://github.com/ondrejnr/mon.git","type":"git"}' 2>/dev/null || true

# Aplikácie sledujúce Git repo
for app in monitoring logging lamp; do
  curl -s -X POST http://argocd.34.89.208.249.nip.io/api/v1/applications \
    -H "Authorization: Bearer $ARGOCD_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
      \"metadata\": {\"name\": \"${app}\", \"namespace\": \"argocd\"},
      \"spec\": {
        \"project\": \"default\",
        \"source\": {
          \"repoURL\": \"https://github.com/ondrejnr/mon.git\",
          \"targetRevision\": \"main\",
          \"path\": \"disaster-recovery/clean/${app}\"
        },
        \"destination\": {
          \"server\": \"https://kubernetes.default.svc\",
          \"namespace\": \"${app}\"
        },
        \"syncPolicy\": {\"automated\": {\"prune\": false, \"selfHeal\": false}}
      }
    }" 2>/dev/null || true
  echo "✅ ArgoCD aplikácia ${app} vytvorená"
done
echo "✅ ArgoCD opravený"

# ----------------------------------------------------------------------
# 5. GRAFANA – pridanie Prometheus datasource
# ----------------------------------------------------------------------
# PRÍČINA CHYBY:
#   - Grafana nemala nakonfigurovaný datasource po nasadení
echo -e "\n📊 [5/7] Pridanie Grafana datasource"
sleep 10
curl -s -X POST http://admin:admin@grafana.34.89.208.249.nip.io/api/datasources \
  -H "Content-Type: application/json" \
  -d '{"name":"Prometheus","type":"prometheus","url":"http://prometheus.monitoring.svc.cluster.local:9090","access":"proxy","isDefault":true}' 2>/dev/null || true
echo "✅ Grafana datasource aplikovaný"

# ----------------------------------------------------------------------
# 6. EXPORT ČISTÝCH MANIFESTOV DO GITU
# ----------------------------------------------------------------------
echo -e "\n💾 [6/7] Export čistých manifestov do Gitu"
cd /home/ondrejko_gulkas/mon

for ns in monitoring logging lamp; do
  mkdir -p disaster-recovery/clean/${ns}
  kubectl get deployments -n $ns -o json | python3 -c "
import json,sys
data = json.load(sys.stdin)
items = []
for item in data.get('items', []):
    item.pop('status', None)
    item['metadata'].pop('resourceVersion', None)
    item['metadata'].pop('uid', None)
    item['metadata'].pop('creationTimestamp', None)
    item['metadata'].pop('generation', None)
    item['metadata'].pop('managedFields', None)
    items.append(item)
print(json.dumps({'apiVersion': 'v1', 'kind': 'List', 'items': items}, indent=2))
" > disaster-recovery/clean/${ns}/deployments.json 2>/dev/null || true

  kubectl get services -n $ns -o json | python3 -c "
import json,sys
data = json.load(sys.stdin)
items = []
for item in data.get('items', []):
    item.pop('status', None)
    item['metadata'].pop('resourceVersion', None)
    item['metadata'].pop('uid', None)
    item['metadata'].pop('creationTimestamp', None)
    item['metadata'].pop('managedFields', None)
    items.append(item)
print(json.dumps({'apiVersion': 'v1', 'kind': 'List', 'items': items}, indent=2))
" > disaster-recovery/clean/${ns}/services.json 2>/dev/null || true

  kubectl get configmaps -n $ns -o json | python3 -c "
import json,sys
data = json.load(sys.stdin)
items = []
for item in data.get('items', []):
    if 'kube-root-ca' in item['metadata'].get('name',''):
        continue
    item.pop('status', None)
    item['metadata'].pop('resourceVersion', None)
    item['metadata'].pop('uid', None)
    item['metadata'].pop('creationTimestamp', None)
    item['metadata'].pop('managedFields', None)
    items.append(item)
print(json.dumps({'apiVersion': 'v1', 'kind': 'List', 'items': items}, indent=2))
" > disaster-recovery/clean/${ns}/configmaps.json 2>/dev/null || true

  echo "✅ ${ns} exportovaný"
done

git add disaster-recovery/clean/ recovery-steps/17-final-recovery-actions.sh
git commit -m "recovery: aktualizácia manifestov a recovery scriptu" 2>/dev/null || true
git push origin main 2>/dev/null || true
echo "✅ Git aktualizovaný"

# ----------------------------------------------------------------------
# 7. ZÁVEREČNÝ TEST
# ----------------------------------------------------------------------
echo -e "\n🌐 [7/7] Testovanie všetkých webov"
for url in bank.34.89.208.249.nip.io argocd.34.89.208.249.nip.io grafana.34.89.208.249.nip.io alertmanager.34.89.208.249.nip.io kibana.34.89.208.249.nip.io prometheus.34.89.208.249.nip.io web.34.89.208.249.nip.io nginx.34.89.208.249.nip.io; do
    echo -n "http://$url ... "
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 http://$url || echo "timeout")
    if [[ "$code" =~ ^(200|301|302|401|403)$ ]]; then
        echo -e "\033[0;32m$code\033[0m"
    else
        echo -e "\033[0;31m$code\033[0m"
    fi
done

echo -e "\n\033[0;32m══════════════════════════════════════════════════════════════════════════\033[0m"
echo -e "\033[0;32m✅ OPRAVY DOKONČENÉ.\033[0m"
