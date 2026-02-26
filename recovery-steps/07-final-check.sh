#!/bin/bash
set -e
echo "=== [7/7] Záverečná kontrola ==="
# Stav podov
kubectl get pods -A | grep -v Running | grep -v Completed || echo "Všetky pody OK"
# Testy webov
echo ""
echo "Testovanie webov:"
for url in bank.34.89.208.249.nip.io argocd.34.89.208.249.nip.io grafana.34.89.208.249.nip.io alertmanager.34.89.208.249.nip.io kibana.34.89.208.249.nip.io prometheus.34.89.208.249.nip.io web.34.89.208.249.nip.io nginx.34.89.208.249.nip.io; do
    echo -n "http://$url ... "
    curl -s -o /dev/null -w "%{http_code}\n" --max-time 5 http://$url
done
# Vygenerovanie hesla pre ArgoCD
echo ""
echo "ArgoCD admin heslo:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""
echo "✅ Kontrola dokončená."
