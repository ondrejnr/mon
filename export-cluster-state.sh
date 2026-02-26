echo "=== EXPORTUJEM STAV CLUSTRA ==="
OUTDIR=/home/ondrejko_gulkas/mon/disaster-recovery
mkdir -p $OUTDIR

echo "--- Namespaces ---"
kubectl get namespaces -o yaml > $OUTDIR/namespaces.yaml

for ns in argocd lamp logging monitoring web web-stack ingress-nginx; do
  echo "--- Exportujem $ns ---"
  mkdir -p $OUTDIR/$ns
  
  kubectl get deployment -n $ns -o yaml > $OUTDIR/$ns/deployments.yaml 2>/dev/null
  kubectl get service -n $ns -o yaml > $OUTDIR/$ns/services.yaml 2>/dev/null
  kubectl get ingress -n $ns -o yaml > $OUTDIR/$ns/ingress.yaml 2>/dev/null
  kubectl get configmap -n $ns -o yaml > $OUTDIR/$ns/configmaps.yaml 2>/dev/null
  kubectl get secret -n $ns -o yaml > $OUTDIR/$ns/secrets.yaml 2>/dev/null
  kubectl get daemonset -n $ns -o yaml > $OUTDIR/$ns/daemonsets.yaml 2>/dev/null
  kubectl get statefulset -n $ns -o yaml > $OUTDIR/$ns/statefulsets.yaml 2>/dev/null
  kubectl get networkpolicy -n $ns -o yaml > $OUTDIR/$ns/networkpolicies.yaml 2>/dev/null
  kubectl get serviceaccount -n $ns -o yaml > $OUTDIR/$ns/serviceaccounts.yaml 2>/dev/null
  kubectl get pvc -n $ns -o yaml > $OUTDIR/$ns/pvcs.yaml 2>/dev/null
done

echo "--- ArgoCD Applications ---"
kubectl get applications -A -o yaml > $OUTDIR/argocd-applications.yaml

echo "--- ClusterRoles ---"
kubectl get clusterrole -o yaml > $OUTDIR/clusterroles.yaml
kubectl get clusterrolebinding -o yaml > $OUTDIR/clusterrolebindings.yaml

echo "--- Vytváram RESTORE skript ---"
cat > $OUTDIR/restore.sh << 'RESTORE'
#!/bin/bash
echo "🚨 DISASTER RECOVERY - OBNOVUJEM CLUSTER"
OUTDIR=$(dirname "$0")

echo "=== [1] NAMESPACES ==="
kubectl apply -f $OUTDIR/namespaces.yaml

echo "=== [2] ARGOCD ==="
kubectl apply -f $OUTDIR/argocd/ --recursive

echo "=== [3] INGRESS NGINX ==="
kubectl apply -f $OUTDIR/ingress-nginx/ --recursive

echo "=== [4] LAMP ==="
kubectl apply -f $OUTDIR/lamp/ --recursive

echo "=== [5] LOGGING ==="
kubectl apply -f $OUTDIR/logging/ --recursive

echo "=== [6] MONITORING ==="
kubectl apply -f $OUTDIR/monitoring/ --recursive

echo "=== [7] WEB ==="
kubectl apply -f $OUTDIR/web/ --recursive
kubectl apply -f $OUTDIR/web-stack/ --recursive

echo "=== [8] ARGOCD APPS ==="
kubectl apply -f $OUTDIR/argocd-applications.yaml

echo "" && echo "=== CAKAM NA PODY ==="
sleep 30
kubectl get pods -A | grep -vE "Running|Completed"

echo "" && echo "=== HTTP TESTY ==="
for url in bank.34.89.208.249.nip.io grafana.34.89.208.249.nip.io alertmanager.34.89.208.249.nip.io prometheus.34.89.208.249.nip.io argocd.34.89.208.249.nip.io kibana.34.89.208.249.nip.io web.34.89.208.249.nip.io nginx.34.89.208.249.nip.io; do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://$url)
  [[ "$code" =~ ^(200|301|302)$ ]] && icon="✅" || icon="❌"
  echo "  $icon $code → http://$url"
done
RESTORE
chmod +x $OUTDIR/restore.sh

echo "" && echo "=== GIT PUSH ==="
cd /home/ondrejko_gulkas/mon
git add disaster-recovery/
git commit -m "feat: disaster recovery - full cluster state export + restore script"
git push origin main

echo "" && echo "=== EXPORTOVANE SUBORY ==="
find $OUTDIR -name "*.yaml" | sort
