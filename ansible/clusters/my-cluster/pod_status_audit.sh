#!/bin/bash
echo "=== STAV MONITORINGU A LOGGINGU ==="
kubectl get pods -n logging
kubectl get pods -n monitoring

echo -e "\n=== POD REŠTARTY (Hľadáme nestabilitu) ==="
kubectl get pods -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount,STATUS:.status.phase | grep -v "Running"
