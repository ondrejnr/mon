#!/bin/bash
echo "=== LOKALNE PORTY A PROCESY ==="
sudo ss -tulnp | grep -E ':(80|443|3000|5601)' || echo "Ziadne lokalne pocuvajuce porty."
ps aux | grep -iE 'grafana|kibana|nginx' | grep -v grep

echo -e "\n=== HLADANIE KUBECONFIGU ==="
KCONF=$(find /home/ondrejko_gulkas/ -maxdepth 5 -type f -name "*kubeconfig*" -o -name "admin.conf" 2>/dev/null | head -n 1)
if [ -n "$KCONF" ]; then
    echo "Pouzivam kubeconfig: $KCONF"
    KUBECONFIG=$KCONF kubectl get nodes
    echo -e "\n--- Pody ---"
    KUBECONFIG=$KCONF kubectl get pods -A | grep -iE 'grafana|kibana|nginx|ingress'
    echo -e "\n--- Ingress ---"
    KUBECONFIG=$KCONF kubectl get ingress -A
else
    echo "Kubeconfig sa nenasiel."
fi
