#!/bin/bash
set -e
echo "═══════════════════════════════════════════════════════════════"
echo "🔧 ZÁVEREČNÉ NASTAVENIE PO OBNOVE"
echo "═══════════════════════════════════════════════════════════════"

# 1. KONTROLA LOGOV A KIBANY
echo ""
echo "📊 [1/5] KONTROLA A NASTAVENIE LOGOV"
NAMESPACE_LOGGING="logging"

# Overenie či Elasticsearch beží
ES_POD=$(kubectl get pods -n $NAMESPACE_LOGGING -l app=elasticsearch -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$ES_POD" ]; then
    echo "❌ Elasticsearch nebeží! Spustite najprv obnovu logging stacku."
    exit 1
fi

# Vygenerovanie test logu (ak nie sú indexy)
INDEX_COUNT=$(kubectl exec -n $NAMESPACE_LOGGING $ES_POD -- curl -s "http://localhost:9200/_cat/indices/logs-lamp-*" | wc -l)
if [ "$INDEX_COUNT" -eq 0 ]; then
    echo "⏳ Indexy neexistujú, generujem testovací log..."
    kubectl exec -n lamp deployment/apache-php -- curl -s http://localhost/ >/dev/null 2>&1 || true
    sleep 10
fi

# Vytvorenie index pattern v Kibane
KIBANA_URL="http://kibana.34.89.208.249.nip.io"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" $KIBANA_URL)
if [ "$HTTP_CODE" == "200" ] || [ "$HTTP_CODE" == "302" ]; then
    curl -s -X POST "$KIBANA_URL/api/saved_objects/index-pattern" \
        -H "kbn-xsrf: true" \
        -H "Content-Type: application/json" \
        -d '{"attributes":{"title":"logs-lamp-*","timeFieldName":"@timestamp"}}' && echo "✅ Index pattern vytvorený" || echo "⚠️ Index pattern už existuje"
else
    echo "❌ Kibana nie je dostupná"
fi

# 2. PRIDANIE REPO DO ARGOCD
echo ""
echo "📦 [2/5] PRIDANIE GIT REPO DO ARGOCD"
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
argocd login argocd.34.89.208.249.nip.io --username admin --password $ARGOCD_PASSWORD --insecure --grpc-web

# Pridanie repa (uprav podľa potreby)
argocd repo add https://github.com/ondrejnr/mon.git --username tvoje_meno --password tvoj_token 2>/dev/null || \
argocd repo add https://github.com/ondrejnr/mon.git --insecure-ignore-host-key

# 3. VYTVORENIE APLIKÁCIÍ V ARGOCD
echo ""
echo "🚀 [3/5] VYTVÁRAM APLIKÁCIE V ARGOCD"
for app in lamp logging monitoring web web-stack; do
    cat << APP | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $app-stack
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/ondrejnr/mon.git
    targetRevision: HEAD
    path: ansible/clusters/my-cluster/$app
  destination:
    server: https://kubernetes.default.svc
    namespace: $app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
APP
done

echo "✅ Aplikácie vytvorené"

# 4. SYNC APLIKÁCIÍ
echo ""
echo "🔄 [4/5] SYNCHRONIZÁCIA APLIKÁCIÍ"
for app in lamp-stack logging-stack monitoring-stack web-stack web-stack; do
    argocd app sync $app --grpc-web || true
done

# 5. KONEČNÝ TEST
echo ""
echo "🌐 [5/5] TESTOVANIE VŠETKÝCH WEBOV"
for url in bank.34.89.208.249.nip.io argocd.34.89.208.249.nip.io grafana.34.89.208.249.nip.io alertmanager.34.89.208.249.nip.io kibana.34.89.208.249.nip.io prometheus.34.89.208.249.nip.io nginx.34.89.208.249.nip.io web.34.89.208.249.nip.io; do
    echo -n "http://$url ... "
    curl -s -o /dev/null -w "%{http_code}\n" --max-time 5 http://$url
done

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ VŠETKY WEBY BY MALI BYŤ FUNKČNÉ"
echo "ArgoCD: admin / $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)"
echo "Kibana: http://kibana.34.89.208.249.nip.io (index pattern 'logs-lamp-*')"
echo "═══════════════════════════════════════════════════════════════"
