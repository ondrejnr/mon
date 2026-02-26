#!/bin/bash
# 1. Oprava APACHE-PHP (Pridanie chýbajúcich portov do Service a fix Image)
kubectl patch svc apache-php -n lamp --type json -p='[
  {"op": "add", "path": "/spec/ports/-", "value": {"name": "apache-metrics", "port": 9117, "targetPort": 9117}},
  {"op": "add", "path": "/spec/ports/-", "value": {"name": "phpfpm-metrics", "port": 9253, "targetPort": 9253}}
]'

# 2. Oprava GRAFANA Scrapingu (Zmena cieľového portu z 80 na 3000)
# Musíme upraviť ServiceMonitor alebo Service, aby Prometheus hľadal na 3000
kubectl patch svc grafana -n monitoring --type json -p='[
  {"op": "replace", "path": "/spec/ports/0/targetPort", "value": 3000}
]'

# 3. Oprava POSTGRESQL (Overenie, či beží exporter)
# Ak postgres nemá exporter kontajner, Prometheus dostane "connection refused"
kubectl patch deployment postgresql -n lamp --type json -p='[
  {"op": "add", "path": "/spec/template/spec/containers/-", "value": {"name": "postgres-exporter", "image": "prometheuscommunity/postgres-exporter:latest", "ports": [{"containerPort": 9187}]}}
]' 2>/dev/null
