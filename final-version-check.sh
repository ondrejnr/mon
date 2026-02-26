#!/bin/bash
set -e
echo "═══════════════════════════════════════════════════════════════"
echo "🔍 ZÁVEREČNÁ KONTROLA KOMPATIBILITY VERZIÍ"
echo "═══════════════════════════════════════════════════════════════"

NAMESPACE="logging"

# 1. Verzia Elasticsearch
ES_VERSION=$(kubectl exec -n $NAMESPACE deployment/elasticsearch -- curl -s "http://localhost:9200" | grep -o '"number":"[^"]*"' | cut -d'"' -f4)
echo "📦 Elasticsearch verzia: $ES_VERSION"

# 2. Verzia Kibany
KIBANA_POD=$(kubectl get pods -n $NAMESPACE -l app=kibana -o jsonpath='{.items[0].metadata.name}')
KIBANA_VERSION=$(kubectl exec -n $NAMESPACE $KIBANA_POD -- node -p "require('./package.json').version" 2>/dev/null || echo "nezistená")
echo "📊 Kibana verzia: $KIBANA_VERSION"

# 3. Verzia Vectora
VECTOR_POD=$(kubectl get pods -n $NAMESPACE -l app=vector -o jsonpath='{.items[0].metadata.name}')
VECTOR_VERSION=$(kubectl exec -n $NAMESPACE $VECTOR_POD -- vector --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "nezistená")
echo "⚙️ Vector verzia: $VECTOR_VERSION"

# 4. Kompatibilita ES a Kibany
echo ""
echo "🔎 KONTROLA KOMPATIBILITY KIBANA <-> ELASTICSEARCH"
if [[ "$ES_VERSION" == "$KIBANA_VERSION" ]]; then
    echo "✅ Verzie Elasticsearch a Kibany sú zhodné ($ES_VERSION)."
elif [[ "$ES_VERSION" =~ ^7\. && "$KIBANA_VERSION" =~ ^7\. ]]; then
    echo "⚠️  Verzie Elasticsearch ($ES_VERSION) a Kibany ($KIBANA_VERSION) sú obe 7.x – v poriadku."
elif [[ "$ES_VERSION" =~ ^8\. && "$KIBANA_VERSION" =~ ^8\. ]]; then
    echo "⚠️  Verzie Elasticsearch ($ES_VERSION) a Kibany ($KIBANA_VERSION) sú obe 8.x – v poriadku, ale vyžadujú správnu bezpečnostnú konfiguráciu."
else
    echo "❌ FATÁLNY PROBLÉM: Elasticsearch ($ES_VERSION) a Kibana ($KIBANA_VERSION) sú nekompatibilné!"
fi

# 5. Kontrola konfigurácie Vectora
echo ""
echo "⚙️ KONTROLA KONFIGURÁCIE VECTORA"
kubectl get configmap vector-config -n $NAMESPACE -o jsonpath='{.data.vector\.yaml}' | grep -E "endpoints:|mode:" || echo "Chýba endpoints alebo mode"

echo ""
echo "═══════════════════════════════════════════════════════════════"
