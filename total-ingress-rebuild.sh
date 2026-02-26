#!/bin/bash
IP="34.89.208.249"

echo "🧪 ZAČÍNAM TOTÁLNU REKONŠTRUKCIU INGRESSU..."

# 1. Odstránenie starých trosiek
kubectl delete namespace ingress-nginx --ignore-not-found
sleep 5
kubectl create namespace ingress-nginx

# 2. Inštalácia Nginx Ingress Controllera (Bare-metal verzia)
echo "📦 Inštalujem čistý Ingress Controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/baremetal/deploy.yaml

# 3. Úprava Service na LoadBalancer s tvojou External IP
echo "🌐 Mapujem porty na IP $IP..."
kubectl patch svc ingress-nginx-controller -n ingress-nginx -p "{\"spec\": {\"type\": \"LoadBalancer\", \"externalIPs\": [\"$IP\"]}}"

# 4. Odstránenie K3s kolízií (Traefik/Servicelb)
echo "🚫 Odstraňujem K3s balancery..."
kubectl delete svc traefik -n kube-system --ignore-not-found
kubectl delete daemonset svclb-traefik -n kube-system --ignore-not-found

echo "⏳ Čakám na inicializáciu podu (60s)..."
sleep 60

# 5. Overenie stavu
kubectl get pods -n ingress-nginx
kubectl get ing -A
