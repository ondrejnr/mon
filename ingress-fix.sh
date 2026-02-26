#!/bin/bash
IP="34.89.208.249"

echo "🧪 ZAČÍNAM HĹBKOVÚ REKONŠTRUKCIU SIEŤOVEJ BRÁNY..."

# 1. Odstránenie automatických balancérov K3s (najčastejšia príčina Pending stavu)
echo "🚫 Odstraňujem kolízne LoadBalancery z kube-system..."
kubectl delete daemonset -n kube-system svclb-ingress-nginx-controller --ignore-not-found
kubectl delete daemonset -n kube-system svclb-ingress-nginx-controller-admission --ignore-not-found

# 2. Vynútené premazanie zaseknutého Ingress podu
echo "🧹 Čistím zaseknutý Ingress pod..."
kubectl delete pod -n ingress-nginx -l app=ingress-nginx --force --grace-period=0

# 3. Čakanie na uvoľnenie socketov v Kerneli
echo "⏳ Čakám 20s na uvoľnenie portu 80..."
sleep 20

# 4. Dynamické vyhľadanie podu podľa tvojho reálneho labelu 'app=ingress-nginx'
echo "🔍 Vyhľadávam nový Ingress pod..."
ING_POD=$(kubectl get pods -n ingress-nginx -l app=ingress-nginx -o name | head -n 1)

if [ -z "$ING_POD" ]; then
    echo "❌ KRITICKÁ CHYBA: Pod nebol nájdený. Skontroluj 'kubectl get pods -n ingress-nginx'."
else
    echo "✅ Pod identifikovaný: $ING_POD"
    echo "⏳ Čakám, kým prejde do stavu Running (max 60s)..."
    kubectl wait --for=condition=Ready $ING_POD -n ingress-nginx --timeout=60s

    echo "🌐 Testujem interné smerovanie na banku..."
    kubectl exec -n ingress-nginx $ING_POD -- curl -I -s -H "Host: bank.$IP.nip.io" http://localhost
fi

echo "📊 Aktuálny stav Ingress adries:"
kubectl get ing -A | grep $IP
