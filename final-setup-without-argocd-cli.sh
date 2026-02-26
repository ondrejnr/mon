#!/bin/bash
set -e
echo "═══════════════════════════════════════════════════════════════"
echo "🔧 ZÁVEREČNÉ NASTAVENIE PO OBNOVE (bez argocd CLI)"
echo "═══════════════════════════════════════════════════════════════"

# 1. KONTROLA A NASTAVENIE LOGOV (už hotové)
echo ""
echo "📊 [1/5] KONTROLA INDEXOV V ELASTICSEARCH"
kubectl exec -n logging deployment/elasticsearch -- curl -s "http://localhost:9200/_cat/indices/logs-lamp-*" || echo "⚠️ Zatiaľ žiadne indexy (počkajte na logy)"

# 2. PRIDANIE REPO DO ARGOCD (cez UI)
echo ""
echo "📦 [2/5] PRIDANIE GIT REPO DO ARGOCD"
echo "   ❌ argocd CLI nie je nainštalované."
echo "   Pridajte repozitár manuálne v ArgoCD UI:"
echo "   1. Prihláste sa do ArgoCD na http://argocd.34.89.208.249.nip.io"
echo "      Používateľ: admin"
echo "      Heslo: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)"
echo "   2. Choďte do Settings → Repositories → Connect Repo"
echo "   3. Vyberte 'VIA HTTPS' a zadajte:"
echo "      Repository URL: https://github.com/ondrejnr/mon.git"
echo "      (ak je repozitár verejný, nemusíte zadávať meno/heslo)"
echo "   4. Kliknite CONNECT"

# 3. VYTVORENIE APLIKÁCIÍ V ARGOCD (cez UI)
echo ""
echo "🚀 [3/5] VYTVÁRAM APLIKÁCIE V ARGOCD (cez kubectl)"
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
echo "✅ Aplikácie vytvorené (automaticky sa zosynchronizujú)"

# 4. KONEČNÝ TEST
echo ""
echo "🌐 [4/5] TESTOVANIE VŠETKÝCH WEBOV"
for url in bank.34.89.208.249.nip.io argocd.34.89.208.249.nip.io grafana.34.89.208.249.nip.io alertmanager.34.89.208.249.nip.io kibana.34.89.208.249.nip.io prometheus.34.89.208.249.nip.io nginx.34.89.208.249.nip.io web.34.89.208.249.nip.io; do
    echo -n "http://$url ... "
    curl -s -o /dev/null -w "%{http_code}\n" --max-time 5 http://$url
done

# 5. ZHRNUTIE
echo ""
echo "📋 [5/5] ZHRNUTIE PRIPOJENIA"
echo "----------------------------------------"
echo "ArgoCD UI: http://argocd.34.89.208.249.nip.io"
echo "  Prihlasovacie meno: admin"
echo "  Heslo: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)"
echo ""
echo "Kibana: http://kibana.34.89.208.249.nip.io"
echo "  Index pattern 'logs-lamp-*' je vytvorený."
echo "  Ak nevidíte žiadne dáta, skontrolujte, či Vector posiela logy:"
echo "  kubectl logs -n logging -l app=vector --tail=20"
echo ""
echo "Grafana: http://grafana.34.89.208.249.nip.io"
echo "Prometheus: http://prometheus.34.89.208.249.nip.io"
echo "Alertmanager: http://alertmanager.34.89.208.249.nip.io"
echo "Bank: http://bank.34.89.208.249.nip.io"
echo "Web: http://web.34.89.208.249.nip.io"
echo "Nginx: http://nginx.34.89.208.249.nip.io"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ VŠETKY SLUŽBY BY MALI BYŤ FUNKČNÉ"
echo "═══════════════════════════════════════════════════════════════"
