#!/bin/bash
echo "=== STAV VŠETKÝCH PODOV V CLUSTERI ==="
kubectl get pods -A | grep -v "Running"

echo -e "\n=== POSLEDNÉ SYSTÉMOVÉ EVENTY (Prečo to stojí?) ==="
kubectl get events -A --sort-by='.lastTimestamp' | tail -n 15
