#!/bin/bash

echo "⚙️ 1. OPRAVA CONFIGU (endpoint -> endpoints)..."
# Oprava syntaxe v ConfigMape pre Vector
kubectl patch configmap vector -n logging --type json -p='[
  {"op": "replace", "path": "/data/vector.yaml", "value": $(kubectl get cm vector -n logging -o jsonpath="{.data.vector\.yaml}" | sed "s/endpoint:/endpoints:/g" | sed "s/\"http/\[\"http/g" | sed "s/80\"/80\"\]/g")}
]' 2>/dev/null

echo "⚙️ 2. TEST KONEKTIVITY Z VECTORA DO ES..."
VECTOR_POD=$(kubectl get pods -n logging -l app.kubernetes.io/name=vector -o name | head -n 1)
kubectl exec -n logging $VECTOR_POD -- curl -s -X GET "http://elasticsearch-master:9200" || echo "❌ Vector nevidí Elasticsearch!"

echo "⚙️ 3. MANUÁLNE VYTVORENIE INDEXU..."
# Vytvoríme dummy log, aby sme "prebudili" Elasticsearch
kubectl exec -n logging $VECTOR_POD -- curl -s -X POST "http://elasticsearch-master:9200/vector-test/_doc" -H 'Content-Type: application/json' -d '{"timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)", "message": "Forenzny test zapisu"}'

echo "🔄 REŠTART VECTORA..."
kubectl rollout restart daemonset vector -n logging

echo "⏳ Čakám na indexy (15s)..."
sleep 15
kubectl exec -n logging svc/elasticsearch-master -- curl -s -X GET "localhost:9200/_cat/indices?v" | grep vector
