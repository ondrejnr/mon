#!/bin/bash
set -e
echo "═══════════════════════════════════════════════════════════════"
echo "🔧 ZJEDNOTENIE VERZIÍ ELASTICSEARCH A KIBANA"
echo "═══════════════════════════════════════════════════════════════"

NAMESPACE="logging"

echo ""
echo "🔍 [1/5] AKTUÁLNE VERZIE"
ES_IMAGE=$(kubectl get deployment elasticsearch -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}')
KIBANA_IMAGE=$(kubectl get deployment kibana -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}')
echo "Elasticsearch: $ES_IMAGE"
echo "Kibana: $KIBANA_IMAGE"

# Zistenie čísel verzií
ES_VERSION=$(echo $ES_IMAGE | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
KIBANA_VERSION=$(echo $KIBANA_IMAGE | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
echo "ES verzia: $ES_VERSION, Kibana verzia: $KIBANA_VERSION"

if [[ "$ES_VERSION" == "$KIBANA_VERSION" ]]; then
    echo "✅ Verzie sú už zhodné."
    exit 0
fi

echo ""
echo "🔄 [2/5] ZMENA KIBANA NA VERZIU $ES_VERSION (rovnakú ako Elasticsearch)"
kubectl set image deployment/kibana -n $NAMESPACE kibana=docker.elastic.co/kibana/kibana:$ES_VERSION

echo ""
echo "⏳ [3/5] ČAKÁM NA REŠTART KIBANA PODU"
kubectl rollout status deployment/kibana -n $NAMESPACE --timeout=120s

echo ""
echo "📋 [4/5] LOGY KIBANA (prvých 10 riadkov)"
sleep 5
kubectl logs -n $NAMESPACE -l app=kibana --tail=10 | grep -E "ready|status|version|error" || true

echo ""
echo "🌐 [5/5] KONTROLA KIBANA ENDPOINTU"
kubectl get ingress -n $NAMESPACE kibana-ingress
echo "Test spojenia:"
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://kibana.34.89.208.249.nip.io

echo ""
echo "✅ VERZIE ZJEDNOTENÉ. Počkaj 30 sekúnd kým sa Kibana úplne nenaštartuje."
echo "Potom otvor http://kibana.34.89.208.249.nip.io"
echo "═══════════════════════════════════════════════════════════════"
