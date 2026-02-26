#!/bin/bash
set -e
echo "═══════════════════════════════════════════════════════════════"
echo "💥 SIMULÁCIA VEĽKEJ HAVÁRIE - MAZANIE VŠETKÝCH NAMESPACOV"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Tento skript ZMAŽE nasledujúce namespacy:"
echo "  - argocd"
echo "  - ingress-nginx"
echo "  - lamp"
echo "  - logging"
echo "  - monitoring"
echo "  - web"
echo "  - web-stack"
echo ""
echo "Po zmazaní spustí obnovu z disaster-recovery a otestuje weby."
echo ""
read -p "Naozaj chcete pokračovať? (ano/nie): " confirm
if [ "$confirm" != "ano" ]; then
    echo "❌ Simulácia zrušená."
    exit 1
fi

# 1. Zmazanie všetkých kritických namespace
echo ""
echo "🔥 [1/5] MAŽEM NAMESPACE..."
for ns in argocd ingress-nginx lamp logging monitoring web web-stack; do
    echo "   Mažem $ns ..."
    kubectl delete namespace $ns --force --grace-period=0 2>/dev/null || true
done

echo "⏳ Čakám 30 sekúnd na dokončenie mazania..."
sleep 30

# 2. Kontrola, či niečo zostalo
echo ""
echo "🔍 [2/5] ZOSTÁVAJÚCE PODY (malo by byť minimum):"
kubectl get pods -A || true

# 3. Spustenie recovery
echo ""
echo "🔄 [3/5] SPÚŠŤAM OBNOVU Z DISASTER-RECOVERY..."
if [ -f /home/ondrejko_gulkas/mon/disaster-recovery/restore.sh ]; then
    /home/ondrejko_gulkas/mon/disaster-recovery/restore.sh
else
    echo "❌ Restore skript neexistuje!"
    exit 1
fi

# 4. Čakanie na ustálenie
echo ""
echo "⏳ [4/5] ČAKÁM 60 SEKÚND NA ROZBEH APLIKÁCIÍ..."
sleep 60

# 5. Testovanie webov
echo ""
echo "🌐 [5/5] TESTOVANIE WEBOV:"
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
echo "✅ SIMULÁCIA DOKONČENÁ"
echo "═══════════════════════════════════════════════════════════════"
