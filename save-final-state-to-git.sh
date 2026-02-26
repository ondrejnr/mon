#!/bin/bash
set -e
echo "═══════════════════════════════════════════════════════════════"
echo "💾 UKLADAM KONEČNÝ FUNKČNÝ STAV DO GIT RECOVERY"
echo "═══════════════════════════════════════════════════════════════"

cd /home/ondrejko_gulkas/mon
NAMESPACE="logging"

# 1. Vytvorenie adresárovej štruktúry
mkdir -p ansible/clusters/my-cluster/{argocd,ingress-nginx,lamp,logging,monitoring,web,web-stack}
mkdir -p disaster-recovery/{argocd,ingress-nginx,lamp,logging,monitoring,web,web-stack}

# 2. Export aktuálnych konfigurácií z klastra (bez metadát)
echo "📦 Exportujem aktuálny stav z klastra..."

# Namespace argocd
kubectl get deployment -n argocd -o yaml | grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > ansible/clusters/my-cluster/argocd/deployments.yaml 2>/dev/null || true
kubectl get service -n argocd -o yaml | grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > ansible/clusters/my-cluster/argocd/services.yaml 2>/dev/null || true
kubectl get ingress -n argocd -o yaml | grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > ansible/clusters/my-cluster/argocd/ingress.yaml 2>/dev/null || true

# Namespace ingress-nginx
kubectl get deployment -n ingress-nginx -o yaml | grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > ansible/clusters/my-cluster/ingress-nginx/deployments.yaml 2>/dev/null || true
kubectl get service -n ingress-nginx -o yaml | grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > ansible/clusters/my-cluster/ingress-nginx/services.yaml 2>/dev/null || true
kubectl get configmap -n ingress-nginx -o yaml | grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > ansible/clusters/my-cluster/ingress-nginx/configmaps.yaml 2>/dev/null || true

# Namespace lamp
kubectl get deployment -n lamp -o yaml | grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > ansible/clusters/my-cluster/lamp/deployments.yaml
kubectl get service -n lamp -o yaml | grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > ansible/clusters/my-cluster/lamp/services.yaml
kubectl get ingress -n lamp -o yaml | grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > ansible/clusters/my-cluster/lamp/ingress.yaml

# Namespace logging (KĽÚČOVÉ - Vector, Elasticsearch, Kibana)
kubectl get deployment -n $NAMESPACE -o yaml | grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > ansible/clusters/my-cluster/logging/deployments.yaml
kubectl get service -n $NAMESPACE -o yaml | grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > ansible/clusters/my-cluster/logging/services.yaml
kubectl get ingress -n $NAMESPACE -o yaml | grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > ansible/clusters/my-cluster/logging/ingress.yaml
kubectl get configmap -n $NAMESPACE -o yaml | grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > ansible/clusters/my-cluster/logging/configmaps.yaml
kubectl get daemonset -n $NAMESPACE -o yaml | grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > ansible/clusters/my-cluster/logging/daemonsets.yaml

# Namespace monitoring
kubectl get deployment -n monitoring -o yaml | grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > ansible/clusters/my-cluster/monitoring/deployments.yaml
kubectl get service -n monitoring -o yaml | grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > ansible/clusters/my-cluster/monitoring/services.yaml
kubectl get ingress -n monitoring -o yaml | grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > ansible/clusters/my-cluster/monitoring/ingress.yaml

# Namespace web
kubectl get deployment -n web -o yaml | grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > ansible/clusters/my-cluster/web/deployments.yaml 2>/dev/null || true
kubectl get service -n web -o yaml | grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > ansible/clusters/my-cluster/web/services.yaml 2>/dev/null || true
kubectl get ingress -n web -o yaml | grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > ansible/clusters/my-cluster/web/ingress.yaml 2>/dev/null || true

# Namespace web-stack
kubectl get deployment -n web-stack -o yaml | grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > ansible/clusters/my-cluster/web-stack/deployments.yaml 2>/dev/null || true
kubectl get service -n web-stack -o yaml | grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > ansible/clusters/my-cluster/web-stack/services.yaml 2>/dev/null || true
kubectl get ingress -n web-stack -o yaml | grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > ansible/clusters/my-cluster/web-stack/ingress.yaml 2>/dev/null || true

# Cluster-wide resources pre Vector
kubectl get clusterrole vector -o yaml | grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > ansible/clusters/my-cluster/logging/vector-clusterrole.yaml 2>/dev/null || true
kubectl get clusterrolebinding vector -o yaml | grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > ansible/clusters/my-cluster/logging/vector-clusterrolebinding.yaml 2>/dev/null || true

# 3. Aktualizácia disaster-recovery kópií
echo "🔄 Kopírujem do disaster-recovery..."
cp -r ansible/clusters/my-cluster/* disaster-recovery/ 2>/dev/null || true

# 4. Vytvorenie aktuálneho restore skriptu
cat > disaster-recovery/restore.sh << 'RESTORE'
#!/bin/bash
set -e
echo "🚨 DISASTER RECOVERY - OBNOVA Z KONEČNÉHO FUNKČNÉHO STAVU"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Aplikácia namespace
kubectl apply -f $SCRIPT_DIR/argocd/ 2>/dev/null || true
kubectl apply -f $SCRIPT_DIR/ingress-nginx/ 2>/dev/null || true
kubectl apply -f $SCRIPT_DIR/lamp/ 2>/dev/null || true
kubectl apply -f $SCRIPT_DIR/logging/ 2>/dev/null || true
kubectl apply -f $SCRIPT_DIR/monitoring/ 2>/dev/null || true
kubectl apply -f $SCRIPT_DIR/web/ 2>/dev/null || true
kubectl apply -f $SCRIPT_DIR/web-stack/ 2>/dev/null || true

# Aplikácia clusterových rolí
kubectl apply -f $SCRIPT_DIR/logging/vector-clusterrole.yaml 2>/dev/null || true
kubectl apply -f $SCRIPT_DIR/logging/vector-clusterrolebinding.yaml 2>/dev/null || true

echo "✅ Obnova dokončená. Čakám 30 sekúnd na stabilizáciu..."
sleep 30
kubectl get pods -A
RESTORE
chmod +x disaster-recovery/restore.sh

# 5. Commit a push do Gitu
echo "📤 Ukladám do Gitu..."
git add ansible/ disaster-recovery/
git commit -m "fix: final working state - all services including logging stack (Vector, ES, Kibana) and vector clusterrole"
git push origin main

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ VŠETKY ZMENY ÚSPEŠNE ULOŽENÉ DO GITU"
echo "📁 Adresár: /home/ondrejko_gulkas/mon/ansible/clusters/my-cluster/"
echo "📁 Disaster recovery: /home/ondrejko_gulkas/mon/disaster-recovery/"
echo "═══════════════════════════════════════════════════════════════"
