#!/bin/bash
echo "=== DIAGNOSTIKA VECTOR -> ELASTICSEARCH ==="
NAMESPACE=logging

# 1. Aktuálna ConfigMap
echo "--- ConfigMap v klastri ---"
kubectl get configmap vector-config -n $NAMESPACE -o yaml | grep -A15 "vector.yaml"

# 2. Čo vidí Vector
echo "--- Obsah /etc/vector/vector.yaml v pode ---"
kubectl exec -n $NAMESPACE -l app=vector -- cat /etc/vector/vector.yaml 2>/dev/null || echo "Nepodarilo sa"

# 3. Verzia Vectora
echo "--- Verzia Vectora ---"
kubectl exec -n $NAMESPACE -l app=vector -- vector --version 2>/dev/null || echo "Neznáma"

# 4. Logy Vectora (posledných 30)
echo "--- Logy Vectora (posledných 30) ---"
kubectl logs -n $NAMESPACE -l app=vector --tail=30

# 5. Existujúce indexy v ES
echo "--- Indexy v Elasticsearch ---"
kubectl exec -n $NAMESPACE deployment/elasticsearch -- curl -s "http://localhost:9200/_cat/indices?v"

# 6. Vygenerovanie test logu a čakanie
echo "--- Generujem test log z banky ---"
kubectl exec -n lamp deployment/apache-php -- curl -s http://localhost/ >/dev/null 2>&1 || true
sleep 10

# 7. Znova indexy
echo "--- Indexy po 10s ---"
kubectl exec -n $NAMESPACE deployment/elasticsearch -- curl -s "http://localhost:9200/_cat/indices?v" | grep lamp || echo "Žiadne lamp indexy"

echo "=== DIAGNOSTIKA DOKONČENÁ ==="
