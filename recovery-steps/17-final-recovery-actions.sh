#!/bin/bash
set -euo pipefail
echo "══════════════════════════════════════════════════════════════════════════"
echo "🔧 KONEČNÉ AKCIE – BANKA, PROMETHEUS, ARGOCD, GRAFANA (UPGRADE)"
echo "══════════════════════════════════════════════════════════════════════════"

NAMESPACE_LAMP="lamp"
NAMESPACE_MONITORING="monitoring"
NAMESPACE_ARGOCD="argocd"

# ----------------------------------------------------------------------
# 1. BANKA – ConfigMap index.php, oprava Apache konfig a phpfpm mountPath
# ----------------------------------------------------------------------
echo -e "\n🏦 [1/6] Oprava banky (index.php, Apache, phpfpm)"

kubectl apply -n $NAMESPACE_LAMP -f - << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: bank-index-php
  namespace: lamp
data:
  index.php: |
    <?php phpinfo(); ?>
