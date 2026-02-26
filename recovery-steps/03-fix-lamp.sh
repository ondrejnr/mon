#!/bin/bash
set -e
echo "=== Oprava banky (PHP-FPM prepojenie) ==="

NAMESPACE="lamp"

# 1. Vytvorenie ConfigMap s konfiguráciou Apache
cat << 'CM' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: apache-php-config
  namespace: lamp
data:
  httpd.conf: |
    ServerName localhost
    LoadModule proxy_module modules/mod_proxy.so
    LoadModule proxy_fcgi_module modules/mod_proxy_fcgi.so
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

# 2. Patch deploymentu – pridanie ConfigMap ako volume a mount
kubectl patch deployment apache-php -n $NAMESPACE --type='json' -p='[
  {"op":"add","path":"/spec/template/spec/volumes/-","value":{"name":"apache-config","configMap":{"name":"apache-php-config"}}},
  {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{"name":"apache-config","mountPath":"/usr/local/apache2/conf/httpd.conf","subPath":"httpd.conf"}}
]' 2>/dev/null || echo "ConfigMap už existuje, pokračujem..."

# 3. Reštart deploymentu
kubectl rollout restart deployment/apache-php -n $NAMESPACE
sleep 10

# 4. Overenie
POD=$(kubectl get pods -n $NAMESPACE -l app=apache-php -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$POD" ]; then
    echo "Test banky:"
    curl -s -o /dev/null -w "HTTP %{http_code}\n" http://bank.34.89.208.249.nip.io
else
    echo "Pod nie je pripravený."
fi
echo "✅ Banka opravená."
