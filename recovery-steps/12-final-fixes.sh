#!/bin/bash
set -e
echo "═══════════════════════════════════════════════════════════════"
echo "🔧 KONEČNÉ OPRAVY – BANKA, ARGOCD, PROMETHEUS, GRAFANA"
echo "═══════════════════════════════════════════════════════════════"

# --------------------------------------------------------------------
# 1. OPRAVA BANKY (Apache MPM a PHP-FPM)
# --------------------------------------------------------------------
echo ""
echo "🏦 [1/5] OPRAVA BANKY"
NAMESPACE_LAMP="lamp"

# Odstránenie starej ConfigMap (ak existuje)
kubectl delete configmap apache-php-config -n $NAMESPACE_LAMP --ignore-not-found

# Vytvorenie novej ConfigMap so správnou konfiguráciou Apache
cat << EOF | kubectl apply -f -
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
