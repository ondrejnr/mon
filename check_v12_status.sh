#!/bin/bash
echo "--- 1. Pod Status (V12) ---"
kubectl get pods -n lamp -l app=apache-php

echo -e "\n--- 2. Resource Usage (Traefik check) ---"
# Overíme, či nám niečo neberie CPU/RAM nečakane
kubectl top pods -n lamp 2>/dev/null || echo "Metrics-server not responding."

echo -e "\n--- 3. Testing Internal DNS inside the new Pod ---"
POD_NAME=$(kubectl get pods -n lamp -l app=apache-php --sort-by=.metadata.creationTimestamp | tail -n 1 | awk '{print $1}')
kubectl exec -n lamp $POD_NAME -c phpfpm -- cat /etc/hosts | grep postgresql || echo "Postgres not in hosts, but DNS should handle it."
