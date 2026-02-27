#!/bin/bash
set -euo pipefail

echo "══════════════════════════════════════════════════════════════════════════"
echo "🔥 ÚPLNÁ OBNOVA KLASTRA DO POSLEDNÉHO FUNKČNÉHO STAVU"
echo "══════════════════════════════════════════════════════════════════════════"

# Premenné
EXTERNAL_IP="34.89.208.249.nip.io"
DOCKER_USER="ondrejnr1"

# 1. Ingress controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/baremetal/deploy.yaml
sleep 10
kubectl patch svc ingress-nginx-controller -n ingress-nginx -p '{"spec":{"type":"LoadBalancer"}}' 2>/dev/null || true
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[0].address}')
kubectl patch svc ingress-nginx-controller -n ingress-nginx -p "{\"spec\":{\"externalIPs\":[\"$NODE_IP\"]}}" 2>/dev/null || true

# 2. Oprava local-path-provisionera
kubectl patch configmap local-path-config -n kube-system --type=merge -p='{
  "data": {
    "config.json": "{\"nodePathMap\":[{\"node\":\"DEFAULT_PATH_FOR_NON_LISTED_NODES\",\"paths\":[\"/opt/local-path-provisioner\"]}]}"
  }
}' 2>/dev/null || true
kubectl rollout restart deployment/local-path-provisioner -n kube-system

# 3. Obnova všetkých manifestov z disaster-recovery
kubectl apply -f disaster-recovery/argocd-applications.yaml
kubectl apply -f disaster-recovery/online-retail/
kubectl apply -f disaster-recovery/monitoring/networkpolicies.yaml

# 4. Obnova ArgoCD aplikácií
kubectl apply -f disaster-recovery/argocd-applications.yaml

# 5. Reštart služieb pre istotu
kubectl rollout restart deployment -n online-retail
kubectl rollout restart statefulset -n online-retail

echo "✅ Obnova dokončená. Počkajte pár minút kým sa všetky služby naštartujú."
