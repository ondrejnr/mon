#!/bin/bash
set -e
NAMESPACE="logging"

echo "=== KONTROLA, ČI LOGY REÁLNE PRICHÁDZAJÚ DO ELASTICSEARCH ==="

# 1. Zisti, či Elasticsearch vôbec beží
echo "--- Stav Elasticsearch podu ---"
kubectl get pods -n $NAMESPACE -l app=elasticsearch

# 2. Pozri logy Elasticsearch (posledných 5)
echo "--- Logy Elasticsearch (posledných 5) ---"
kubectl logs -n $NAMESPACE -l app=elasticsearch --tail=5

# 3. Koľko dokumentov je celkovo v indexoch logs-lamp
echo "--- Počet dokumentov v logs-lamp indexoch ---"
TOTAL_DOCS=$(kubectl exec -n $NAMESPACE deployment/elasticsearch -- curl -s "http://localhost:9200/_cat/indices/logs-lamp-*?h=docs.count" | awk '{sum+=$1} END {print sum}')
if [ -z "$TOTAL_DOCS" ] || [ "$TOTAL_DOCS" -eq 0 ]; then
    echo "❌ Žiadne dokumenty v logs-lamp indexoch!"
else
    echo "✅ Celkový počet dokumentov: $TOTAL_DOCS"
fi

# 4. Pozrieť posledných 5 dokumentov (aby sme videli štruktúru)
echo "--- Posledných 5 logov v Elasticsearch ---"
kubectl exec -n $NAMESPACE deployment/elasticsearch -- curl -s "http://localhost:9200/logs-lamp-*/_search?size=5&sort=@timestamp:desc" | jq '.hits.hits[] | {_index, _source: {message, kubernetes: ._source.kubernetes.pod_name, timestamp: ._source.@timestamp}}' 2>/dev/null || echo "Žiadne logy alebo jq nie je nainštalované"

# 5. Ak sú logy v Elasticsearch, problém je v Kibane
if [ -n "$TOTAL_DOCS" ] && [ "$TOTAL_DOCS" -gt 0 ]; then
    echo "✅ Logy sú v Elasticsearch, problém je v Kibane:"
    echo "   - Skontrolujte, či index pattern používa správny názov (mal by byť 'logs-lamp-*')"
    echo "   - V Discover skúste zmeniť časový filter na 'Last 1 hour' alebo 'Last 24 hours'"
    echo "   - Skontrolujte, či pole @timestamp existuje v každom dokumente"
fi

# 6. Ak nie sú logy v Elasticsearch, problém je inde
if [ -z "$TOTAL_DOCS" ] || [ "$TOTAL_DOCS" -eq 0 ]; then
    echo "❌ Logy nie sú v Elasticsearch, problém je inde:"
    echo "   - Skontrolujte Vector logy (kubectl logs -n logging -l app=vector --tail=20)"
    echo "   - Skontrolujte, či Vector konfigurácia ukazuje na elasticsearch.logging:9200"
    echo "   - Skontrolujte, či Elasticsearch nie je preťažený"
fi

echo "=== HOTOVO ==="
