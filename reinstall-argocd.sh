#!/bin/bash
set -e
echo "═══════════════════════════════════════════════════════════════"
echo "🔄 ČISTÁ REINŠTALÁCIA ARGOCD"
echo "═══════════════════════════════════════════════════════════════"

NAMESPACE="argocd"

# 1. Odstránenie starého ArgoCD (ak existuje)
echo ""
echo "🗑️ [1/5] Odstraňujem starú inštaláciu ArgoCD..."
kubectl delete namespace $NAMESPACE --force --grace-period=0 2>/dev/null || true
sleep 10

# 2. Vytvorenie namespace
echo ""
echo "📁 [2/5] Vytváram namespace $NAMESPACE"
kubectl create namespace $NAMESPACE

# 3. Inštalácia ArgoCD z oficiálneho manifestu
echo ""
echo "🚀 [3/5] Inštalujem ArgoCD (čakám cca 60 sekúnd)..."
kubectl apply -n $NAMESPACE -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 4. Počkám na všetky deploymenty
echo ""
echo "⏳ [4/5] Čakám na spustenie všetkých podov..."
kubectl wait --for=condition=available --timeout=120s deployment -n $NAMESPACE --all || true
sleep 20

# 5. Pridanie --insecure do argocd-server
echo ""
echo "🔧 [5/5] Konfigurujem argocd-server s --insecure"
kubectl patch deployment argocd-server -n $NAMESPACE --type='json' -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--insecure"}]'
kubectl rollout restart deployment/argocd-server -n $NAMESPACE
sleep 15

# 6. Vytvorenie Ingress pre ArgoCD
cat << INGRESS | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-final
  namespace: $NAMESPACE
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

echo ""
echo "✅ Inštalácia dokončená. Čakám na rozbehnutie..."
sleep 10

echo ""
echo "📦 Stav podov:"
kubectl get pods -n $NAMESPACE

echo ""
echo "🌐 Test ArgoCD:"
curl -I http://argocd.34.89.208.249.nip.io

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "🎉 ArgoCD by malo byť dostupné na http://argocd.34.89.208.249.nip.io"
echo "═══════════════════════════════════════════════════════════════"
