#!/bin/bash

echo "🕵️ ANALÝZA LOGOV EXPORTERA..."
kubectl logs -n lamp -l app=apache-php -c apache-exporter --tail=20

echo "⚙️ OPRAVA START-UP ARGUMENTOV (Vynútenie portov)..."
# Prestavíme exportéry tak, aby počúvali na všetkých rozhraniach a bez sond
kubectl patch deployment apache-php -n lamp --type json -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/2/args", "value": ["--telemetry.address=:9117", "--scrape_uri=http://localhost/server-status?auto"]},
  {"op": "replace", "path": "/spec/template/spec/containers/3/args", "value": ["--phpfpm.scrape-uri=tcp://127.0.0.1:9000/status"]}
]' 2>/dev/null

echo "☢️ TVRDÝ REŠTART (Force Delete)..."
kubectl delete pod -n lamp -l app=apache-php --force --grace-period=0

echo "⏳ Čakám na inicializáciu (20s)..."
sleep 20
kubectl get pods -n lamp -o wide
