#!/bin/bash
set -e
OUTDIR=$(dirname "$0")
echo "🚨 DISASTER RECOVERY START - $(date)"

echo "=== [1] NAMESPACES ==="
for ns in lamp logging monitoring web web-stack ingress-nginx; do
  kubectl create namespace $ns 2>/dev/null || echo "  $ns už existuje"
done

echo "=== [2] INGRESS NGINX ==="
kubectl apply -f $OUTDIR/ingress-nginx/serviceaccounts.yaml 2>/dev/null || true
kubectl apply -f $OUTDIR/ingress-nginx/configmaps.yaml 2>/dev/null || true
kubectl apply -f $OUTDIR/ingress-nginx/deployments.yaml
kubectl apply -f $OUTDIR/ingress-nginx/services.yaml
echo "  Cakam na ingress-nginx webhook..."
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=ingress-nginx \
  -n ingress-nginx --timeout=120s 2>/dev/null || true

echo "=== [3] ARGOCD ==="
kubectl apply -f $OUTDIR/argocd/configmaps.yaml 2>/dev/null || true
kubectl apply -f $OUTDIR/argocd/secrets.yaml 2>/dev/null || true
kubectl apply -f $OUTDIR/argocd/serviceaccounts.yaml 2>/dev/null || true
kubectl apply -f $OUTDIR/argocd/services.yaml 2>/dev/null || true
kubectl apply -f $OUTDIR/argocd/deployments.yaml 2>/dev/null || true
kubectl apply -f $OUTDIR/argocd/statefulsets.yaml 2>/dev/null || true
kubectl apply -f $OUTDIR/argocd/ingress.yaml 2>/dev/null || true
echo "  Cakam na argocd-server..."
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=argocd-server \
  -n argocd --timeout=120s 2>/dev/null || true

echo "=== [4-7] APLIKACIE cez ArgoCD ==="
kubectl apply -f $OUTDIR/argocd-applications.yaml
echo "  ArgoCD preberá kontrolu - cakam 60s..."
sleep 60

echo "=== [8] INGRESS (po webhook ready) ==="
for ns in lamp logging monitoring web web-stack; do
  kubectl apply -f $OUTDIR/$ns/ingress.yaml 2>/dev/null || true
done

echo "" && echo "=== FINALNE CAKANIE (30s) ==="
sleep 30

echo "" && echo "=== STAV PODOV ==="
kubectl get pods -A | grep -vE "Running|Completed" || echo "✅ Vsetky pody OK"

echo "" && echo "=== HTTP TESTY ==="
for url in bank.34.89.208.249.nip.io grafana.34.89.208.249.nip.io \
  alertmanager.34.89.208.249.nip.io prometheus.34.89.208.249.nip.io \
  argocd.34.89.208.249.nip.io kibana.34.89.208.249.nip.io \
  web.34.89.208.249.nip.io nginx.34.89.208.249.nip.io; do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://$url)
  [[ "$code" =~ ^(200|301|302)$ ]] && icon="✅" || icon="❌"
  echo "  $icon $code → http://$url"
done
echo "🏁 RECOVERY HOTOVÁ - $(date)"
