#!/bin/bash
set -e
echo "═══════════════════════════════════════════════════════════════"
echo "🔍 DIAGNOSTIKA A OPRAVA PO OB N OVE"
echo "═══════════════════════════════════════════════════════════════"

# 1. Stav ArgoCD
echo ""
echo "📦 [1/5] STAV ARGOCD PODOV"
kubectl get pods -n argocd || echo "❌ ArgoCD namespace neexistuje"
ARGOCD_SERVER=$(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$ARGOCD_SERVER" ]; then
    READY=$(kubectl get pod -n argocd $ARGOCD_SERVER -o jsonpath='{.status.phase}')
    if [ "$READY" = "Running" ]; then
        echo "✅ ArgoCD server beží"
    else
        echo "❌ ArgoCD server nie je v stave Running (aktuálne: $READY)"
        kubectl logs -n argocd $ARGOCD_SERVER --tail=20
    fi
else
    echo "❌ ArgoCD server pod neexistuje"
fi

# 2. Ingress pre ArgoCD
echo ""
echo "🌐 [2/5] INGRESS PRE ARGOCD"
kubectl get ingress -n argocd argocd-final -o yaml | grep -A10 "rules:" || echo "❌ Ingress argocd-final neexistuje"

# 3. Banka – kontrola prepojenia Apache a PHP-FPM
echo ""
echo "🏦 [3/5] KONTROLA BANKY"
kubectl get configmap -n lamp apache-php-config &>/dev/null && echo "✅ ConfigMap apache-php-config existuje" || echo "❌ ConfigMap apache-php-config neexistuje (treba spustiť 03-fix-lamp.sh)"
APACHE_POD=$(kubectl get pods -n lamp -l app=apache-php -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$APACHE_POD" ]; then
    echo "Apache pod: $APACHE_POD"
    # Zisti, či je conf pripojený
    MOUNT=$(kubectl exec -n lamp $APACHE_POD -c apache -- cat /usr/local/apache2/conf/httpd.conf 2>/dev/null | grep -c "proxy_fcgi" || true)
    if [ "$MOUNT" -gt 0 ]; then
        echo "✅ Apache konfigurácia obsahuje proxy_fcgi"
    else
        echo "❌ Apache nemá správnu konfiguráciu (chyba 03-fix-lamp.sh)"
    fi
else
    echo "❌ Pod banky neexistuje"
fi

# 4. Ak ArgoCD nie je dostupné, skúsime reštartovať ingress controller
echo ""
echo "🔄 [4/5] KONTROLA INGRESS CONTROLLERA"
kubectl get pods -n ingress-nginx | grep controller
INGRESS_POD=$(kubectl get pods -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$INGRESS_POD" ]; then
    kubectl logs -n ingress-nginx $INGRESS_POD --tail=5 | grep -E "WARN|ERROR" || echo "Žiadne chyby v logoch"
else
    echo "❌ Ingress controller nebeží"
fi

# 5. Ak je všetko v poriadku, spustíme opravu
echo ""
echo "🔧 [5/5] SPÚŠŤAM OPRAVY"
if [ ! -f /home/ondrejko_gulkas/mon/recovery-steps/03-fix-lamp.sh ]; then
    echo "❌ Skript 03-fix-lamp.sh neexistuje, vytváram..."
    cat > /home/ondrejko_gulkas/mon/recovery-steps/03-fix-lamp.sh << 'FIX'
#!/bin/bash
set -e
echo "=== Oprava banky (prepojenie Apache ↔ PHP-FPM) ==="
NAMESPACE="lamp"
# ConfigMap
cat << 'CM' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: apache-php-config
  namespace: $NAMESPACE
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
# Patch deploymentu
kubectl patch deployment apache-php -n $NAMESPACE --type='json' -p='[
  {"op":"add","path":"/spec/template/spec/volumes/-","value":{"name":"apache-config","configMap":{"name":"apache-php-config"}}},
  {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{"name":"apache-config","mountPath":"/usr/local/apache2/conf/httpd.conf","subPath":"httpd.conf"}}
]' 2>/dev/null || echo "ConfigMap už existuje, pokračujem..."
kubectl rollout restart deployment/apache-php -n $NAMESPACE
sleep 15
echo "✅ Banka opravená."
FIX
    chmod +x /home/ondrejko_gulkas/mon/recovery-steps/03-fix-lamp.sh
fi

# Spustíme opravu banky (ak treba)
echo "Spúšťam 03-fix-lamp.sh..."
/home/ondrejko_gulkas/mon/recovery-steps/03-fix-lamp.sh

# Reštartujeme ingress controller (pre istotu)
kubectl rollout restart deployment/ingress-nginx-controller -n ingress-nginx
sleep 20

# Záverečný test
echo ""
echo "🌐 ZÁVEREČNÝ TEST WEBOV"
for url in bank.34.89.208.249.nip.io argocd.34.89.208.249.nip.io grafana.34.89.208.249.nip.io alertmanager.34.89.208.249.nip.io kibana.34.89.208.249.nip.io prometheus.34.89.208.249.nip.io web.34.89.208.249.nip.io nginx.34.89.208.249.nip.io; do
    echo -n "http://$url ... "
    curl -s -o /dev/null -w "%{http_code}\n" --max-time 10 http://$url
done

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ DIAGNOSTIKA A OPRAVA DOKONČENÁ"
echo "═══════════════════════════════════════════════════════════════"
