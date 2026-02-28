#!/bin/bash
set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✅ $*${NC}"; }
err()  { echo -e "${RED}❌ $*${NC}"; exit 1; }
info() { echo -e "${CYAN}ℹ️  $*${NC}"; }
step() { echo -e "\n${BOLD}═══════════════════════════════════════════${NC}"; echo -e "${BOLD}$*${NC}"; echo -e "${BOLD}═══════════════════════════════════════════${NC}"; }

step "📦 [11/16] INŠTALÁCIA CLICKHOUSE"

kubectl create namespace clickhouse-operator --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace clickhouse --dry-run=client -o yaml | kubectl apply -f -

info "Pridávam Altinity ClickHouse repozitár..."
helm repo add altinity https://altinity.github.io/clickhouse-operator/ || true
helm repo update

info "Inštalujem clickhouse-operator cez Helm..."
helm upgrade --install clickhouse-operator altinity/altinity-clickhouse-operator \
  -n clickhouse-operator --wait --timeout 5m

info "Aplikujem ClickHouseInstallation..."
cat << 'EOF' | kubectl apply -f -
apiVersion: clickhouse.altinity.com/v1
kind: ClickHouseInstallation
metadata:
  name: clickhouse
  namespace: clickhouse
spec:
  configuration:
    users:
      clickhouse_operator/password: clickhouse_operator_password
      default/password: default
    clusters:
      - name: default
        layout:
          shardsCount: 1
          replicasCount: 1
  templates:
    volumeClaimTemplates:
      - name: data
        spec:
          accessModes:
            - ReadWriteOnce
          storageClassName: local-path
          resources:
            requests:
              storage: 10Gi
EOF

info "Čakám na ClickHouse pody..."
kubectl wait --for=condition=ready pod -l app=clickhouse -n clickhouse --timeout=300s || true

ok "ClickHouse inštalácia dokončená"
