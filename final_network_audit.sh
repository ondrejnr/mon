#!/bin/bash
echo "--- 1. Service Endpoints (Public & Monitoring) ---"
kubectl get endpoints apache-php -n lamp

echo -e "\n--- 2. Ingress Traffic Check ---"
kubectl describe ingress apache-ingress -n lamp | grep -A 2 "Backends"

echo -e "\n--- 3. Testing Prometheus Metrics Ports ---"
POD_IP=$(kubectl get pod -n lamp -l app=apache-php -o jsonpath='{.items[0].status.podIP}')
echo "Apache Exporter (9117):"
kubectl exec -n lamp -it apache-php-6cb9c85db8-6bt95 -c apache -- wget -qO- localhost:9117/metrics | head -n 3
