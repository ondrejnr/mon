#!/bin/bash
IP="34.89.208.249"

echo "🧪 ZAČÍNAM SYSTÉMOVÚ DEBLOKÁCIU PORTOV..."

# 1. Agresívne odstránenie všetkých Service LoadBalancerov, ktoré môžu blokovať porty
echo "🚫 Čistím K3s sieťové zvyšky..."
kubectl delete daemonset -n kube-system svclb-ingress-nginx-controller --ignore-not-found
kubectl delete daemonset -n kube-system svclb-ingress-nginx-controller-admission --ignore-not-found

# 2. Kontrola, či port 80 nedrží niečo mimo Kubernetes (napr. lokálny apache/nginx)
echo "🔍 Kontrolujem OS sockety na porte 80..."
fuser -k 80/tcp 2>/dev/null # Pokus o zabitie procesu držiaceho port 80

# 3. Vynútený reštart Ingressu
echo "🔄 Reštartujem Ingress Controller..."
kubectl rollout restart deployment -n ingress-nginx
sleep 15

# 4. Hľadanie podu podľa správneho labelu 'app=ingress-nginx'
ING_POD=$(kubectl get pods -n ingress-nginx -l app=ingress-nginx -o name | head -n 1)

if [ -z "$ING_POD" ]; then
    echo "❌ Pod stále neexistuje. Kontrolujem dôvody v schedulerovi:"
    kubectl describe pod -n ingress-nginx -l app=ingress-nginx | grep -A 5 "Events"
else
    echo "✅ Pod nájdený: $ING_POD"
    echo "⏳ Čakám na stav Running..."
    kubectl wait --for=condition=Ready $ING_POD -n ingress-nginx --timeout=30s
    
    echo "🌐 Testujem interný routing na banku..."
    kubectl exec -n ingress-nginx $ING_POD -- curl -I -s -H "Host: bank.$IP.nip.io" http://localhost
fi

echo "📊 Aktuálny prehľad Ingress adries:"
kubectl get ing -A
