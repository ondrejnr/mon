#!/bin/bash
set -e
echo "=== [1/7] Ingress controller ==="
# Vytvorenie namespace (ak neexistuje)
kubectl create namespace ingress-nginx 2>/dev/null || true
# Aplikácia oficiálneho manifestu
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/baremetal/deploy.yaml
# Zmena na LoadBalancer + externalIP
sleep 10
kubectl patch svc ingress-nginx-controller -n ingress-nginx -p '{"spec":{"type":"LoadBalancer"}}' 2>/dev/null || true
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[0].address}')
kubectl patch svc ingress-nginx-controller -n ingress-nginx -p "{\"spec\":{\"externalIPs\":[\"$NODE_IP\"]}}"
echo "✅ Ingress controller ready. Čakám 20s..."
sleep 20
kubectl get pods -n ingress-nginx
