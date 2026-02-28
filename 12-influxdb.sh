#!/bin/bash
set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✅ $*${NC}"; }
err()  { echo -e "${RED}❌ $*${NC}"; exit 1; }
info() { echo -e "${CYAN}ℹ️  $*${NC}"; }
step() { echo -e "\n${BOLD}═══════════════════════════════════════════${NC}"; echo -e "${BOLD}$*${NC}"; echo -e "${BOLD}═══════════════════════════════════════════${NC}"; }

step "📦 [12/16] INŠTALÁCIA INFLUXDB"

kubectl create namespace influxdb --dry-run=client -o yaml | kubectl apply -f -

info "Pridávam InfluxData repozitár..."
helm repo add influxdata https://helm.influxdata.com/ || true
helm repo update

info "Inštalujem influxdb cez Helm..."
cat << 'EOF' > /tmp/influxdb-values.yaml
persistence:
  enabled: true
  storageClass: "local-path"
  size: 10Gi
EOF

helm upgrade --install influxdb influxdata/influxdb \
  -n influxdb -f /tmp/influxdb-values.yaml \
  --set env[0].name=INFLUXDB_DB,env[0].value=metrics \
  --set env[1].name=INFLUXDB_ADMIN_USER,env[1].value=admin \
  --set env[2].name=INFLUXDB_ADMIN_PASSWORD,env[2].value=adminpassword \
  --wait --timeout 5m

rm -f /tmp/influxdb-values.yaml

ok "InfluxDB inštalácia dokončená"
