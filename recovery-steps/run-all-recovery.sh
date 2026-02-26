#!/bin/bash
set -e
echo "Spúšťam kompletnú obnovu v 7 krokoch..."
for step in 01-setup-ingress.sh 02-setup-logging.sh 03-setup-lamp.sh 04-setup-monitoring.sh 05-setup-web.sh 06-setup-argocd.sh 07-final-check.sh; do
    echo ""
    echo ">>> Spúšťam $step"
    ./$step
    echo ">>> $step dokončený"
    sleep 5
done
echo "Všetky kroky úspešne dokončené."
