#!/bin/bash
echo "=== POSLEDNÝCH 20 RIADKOV LOGOV VECTORU ==="
kubectl logs -n logging -l app.kubernetes.io/name=vector --previous --tail=20

echo -e "\n=== KONTROLA CONFIGMAPY (Hľadáme chyby v syntaxi) ==="
kubectl get cm vector-config -n logging -o yaml
