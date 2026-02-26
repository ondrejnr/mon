echo "=== HLADAM NGINX A APACHE WEBY ==="
kubectl get ingress -A | grep -iE "nginx|apache|web"
kubectl get svc -A | grep -iE "nginx|apache|web"
kubectl get pods -A | grep -iE "nginx|apache|web"

echo "" && echo "=== NAMESPACES web a web-stack ==="
kubectl get all -n web 2>/dev/null || echo "web: prazdny"
kubectl get all -n web-stack 2>/dev/null || echo "web-stack: prazdny"

echo "" && echo "=== ARGOCD APPS PRE WEB ==="
kubectl get applications -A | grep -iE "web|nginx|apache"

echo "" && echo "=== GIT REPO - WEB MANIFESTY ==="
find /home/ondrejko_gulkas/mon -name "*.yaml" | xargs grep -l "nginx\|apache" 2>/dev/null | grep -v backup
