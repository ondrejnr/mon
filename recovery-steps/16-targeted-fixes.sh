#!/bin/bash
set -euo pipefail
echo "══════════════════════════════════════════════════════════════════════════"
echo "🔧 CIELENÉ OPRAVY – BANKA, PROMETHEUS, ARGOCD"
echo "══════════════════════════════════════════════════════════════════════════"

NAMESPACE_LAMP="lamp"
NAMESPACE_MONITORING="monitoring"
NAMESPACE_ARGOCD="argocd"

# ----------------------------------------------------------------------
# 1. OPRAVA BANKY (Apache – chýbajúci Listen 80)
# ----------------------------------------------------------------------
echo -e "\n🏦 [1/4] Oprava Apache konfigurácie (Listen 80)"
kubectl delete configmap apache-php-config -n $NAMESPACE_LAMP --ignore-not-found
cat << 'CM' | kubectl apply -f -
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
    DocumentRoot /usr/local/apache2/htdocs
    <Directory /usr/local/apache2/htdocs>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    <FilesMatch \.php$>
        SetHandler proxy:fcgi://127.0.0.1:9000
    </FilesMatch>
CM

# Znovu pripojíme ConfigMap (ak ešte nie je)
kubectl patch deployment apache-php -n $NAMESPACE_LAMP --type='json' -p='[
  {"op":"add","path":"/spec/template/spec/volumes/-","value":{"name":"apache-config","configMap":{"name":"apache-php-config"}}},
  {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{"name":"apache-config","mountPath":"/usr/local/apache2/conf/httpd.conf","subPath":"httpd.conf"}}
]' 2>/dev/null || echo "Patch pravdepodobne už existuje."

# Reštartujeme pod (vymažeme starý)
kubectl delete pod -n $NAMESPACE_LAMP -l app=apache-php --force --grace-period=0 2>/dev/null || true
sleep 10

# Počkáme na nový pod
kubectl wait --for=condition=ready pod -l app=apache-php -n $NAMESPACE_LAMP --timeout=60s || echo "⚠️ Pod nie je ready, skontroluj logy."
kubectl logs -n $NAMESPACE_LAMP -l app=apache-php -c apache --tail=10

# ----------------------------------------------------------------------
# 2. PROMETHEUS – PRIDANIE RBAC PRÁV
# ----------------------------------------------------------------------
echo -e "\n📈 [2/4] Pridanie RBAC pre Prometheus (čítanie podov)"
cat << 'RBAC' | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus
rules:
- apiGroups: [""]
  resources: ["pods", "services", "endpoints"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prometheus
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: prometheus
subjects:
- kind: ServiceAccount
  name: default
  namespace: monitoring
RBAC

# Reštartujeme Prometheus
kubectl rollout restart deployment/prometheus -n $NAMESPACE_MONITORING
sleep 15

# ----------------------------------------------------------------------
# 3. ARGOCD – ZABRÁNENIE PRESMEROVANIU NA HTTPS
# ----------------------------------------------------------------------
echo -e "\n🚀 [3/4] Oprava ArgoCD presmerovania (307)"
# Pridáme anotáciu ssl-redirect=false
kubectl annotate ingress argocd-final -n $NAMESPACE_ARGOCD nginx.ingress.kubernetes.io/ssl-redirect="false" --overwrite

# Overíme, že argocd-server má --insecure
if ! kubectl get deployment argocd-server -n $NAMESPACE_ARGOCD -o jsonpath='{.spec.template.spec.containers[0].args}' | grep -q --insecure; then
    echo "Pridávam --insecure do argocd-server"
    kubectl patch deployment argocd-server -n $NAMESPACE_ARGOCD --type='json' -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--insecure"}]'
    kubectl rollout restart deployment/argocd-server -n $NAMESPACE_ARGOCD
    sleep 15
else
    echo "✅ --insecure už je prítomný."
fi

# ----------------------------------------------------------------------
# 4. ZÁVEREČNÝ TEST
# ----------------------------------------------------------------------
echo -e "\n🌐 [4/4] Testovanie webov"
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
echo -e "\033[0;32m✅ CIELENÉ OPRAVY DOKONČENÉ. Počkajte pár minút na zber metrík.\033[0m"
