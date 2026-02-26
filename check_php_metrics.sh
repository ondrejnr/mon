#!/bin/bash
POD_NAME=$(kubectl get pods -n lamp -l app=apache-php -o jsonpath='{.items[0].metadata.name}')
echo "--- Testing PHP-FPM Metrics (Port 9253) ---"
kubectl exec -n lamp $POD_NAME -c apache -- wget -qO- localhost:9253/metrics | grep "phpfpm_up" || echo "PHP metrics not ready yet."
