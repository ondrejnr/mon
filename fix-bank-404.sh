#!/bin/bash
echo "═══════════════════════════════════════════════════════════════"
echo "🔍 DIAGNOSTIKA BANKY (HTTP 404)"
echo "═══════════════════════════════════════════════════════════════"

NAMESPACE="lamp"
POD=$(kubectl get pods -n $NAMESPACE -l app=apache-php -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$POD" ]; then
    echo "❌ Pod banky nenájdený!"
    exit 1
fi

echo "📦 Pod: $POD"

# 1. Zisti, čo je v document root
echo ""
echo "📁 Obsah /var/www/html:"
kubectl exec -n $NAMESPACE $POD -- ls -la /var/www/html/ 2>/dev/null || echo "❌ Adresár neexistuje"

# 2. Hľadaj index.php
echo ""
echo "📄 Existuje index.php?"
kubectl exec -n $NAMESPACE $POD -- find /var/www/html -name "index.php" 2>/dev/null | head -5 || echo "❌ index.php nenájdený"

# 3. Pozri sa do logov Apache
echo ""
echo "📜 Logy Apache (posledných 10):"
kubectl logs -n $NAMESPACE $POD -c apache --tail=10 2>/dev/null || echo "Žiadne logy"

# 4. Otestuj, či Apache vôbec odpovedá interne
echo ""
echo "🔌 Test internej odpovede Apache:"
kubectl exec -n $NAMESPACE $POD -c apache -- curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost/ || echo "❌ Neodpovedá"

# 5. Ak index.php chýba, skús ho vytvoriť (jednoduchý)
if ! kubectl exec -n $NAMESPACE $POD -- test -f /var/www/html/index.php &>/dev/null; then
    echo ""
    echo "🛠️ Vytváram jednoduchý index.php..."
    kubectl exec -n $NAMESPACE $POD -c apache -- sh -c "echo '<?php phpinfo(); ?>' > /var/www/html/index.php"
    echo "✅ index.php vytvorený"
fi

echo ""
echo "=== KONEČNÝ TEST BANKY ==="
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://bank.34.89.208.249.nip.io

echo "═══════════════════════════════════════════════════════════════"
