#!/bin/bash
echo "═══════════════════════════════════════════════════════════════"
echo "🔍 RÝCHLA DIAGNOSTIKA PO HAVÁRII"
echo "═══════════════════════════════════════════════════════════════"

echo ""
echo "📦 [1/6] STAV INGRESS CONTROLLERU"
kubectl get pods -n ingress-nginx
echo ""
echo "Logy ingress controlleru (posledných 10):"
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=10 2>/dev/null || echo "Žiadne logy"

echo ""
echo "🌐 [2/6] EXISTUJÚCE INGRESSY"
kubectl get ingress -A

echo ""
echo "🔌 [3/6] ENDPOINTY PRE SLUŽBY"
kubectl get endpoints -A | grep -E "apache-php|grafana|alertmanager|kibana|nginx"

echo ""
echo "📦 [4/6] STAV PODOV (nie Running)"
kubectl get pods -A | grep -v Running | grep -v Completed || echo "Všetky pody sú v poriadku"

echo ""
echo "📜 [5/6] LOGY VECTORA (pre istotu)"
kubectl logs -n logging -l app=vector --tail=5 2>/dev/null || echo "Vector nie je"

echo ""
echo "🌍 [6/6] HTTP TESTY"
for url in $(kubectl get ingress -A -o jsonpath='{range .items[*]}{.spec.rules[*].host}{"\n"}{end}' 2>/dev/null | sort -u); do
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://$url)
    if [[ "$code" =~ ^(200|301|302)$ ]]; then
        echo "   ✅ $code http://$url"
    else
        echo "   ❌ $code http://$url"
    fi
done

echo ""
echo "═══════════════════════════════════════════════════════════════"
