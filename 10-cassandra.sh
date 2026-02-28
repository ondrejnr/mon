#!/bin/bash
set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✅ $*${NC}"; }
err()  { echo -e "${RED}❌ $*${NC}"; exit 1; }
info() { echo -e "${CYAN}ℹ️  $*${NC}"; }
step() { echo -e "\n${BOLD}═══════════════════════════════════════════${NC}"; echo -e "${BOLD}$*${NC}"; echo -e "${BOLD}═══════════════════════════════════════════${NC}"; }

step "📦 [10/16] INŠTALÁCIA CASSANDRA"

# Inštalácia cert-manager (prerekvizita pre cass-operator)
if ! kubectl get ns cert-manager &>/dev/null; then
  info "Inštalujem cert-manager (prerekvizita)..."
  kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.3/cert-manager.yaml
  kubectl wait --for=condition=ready pod -l app=cert-manager -n cert-manager --timeout=120s
fi

kubectl create namespace cassandra --dry-run=client -o yaml | kubectl apply -f -

info "Pridávam k8ssandra Helm repozitár..."
helm repo add k8ssandra https://helm.k8ssandra.io/  || true
helm repo update

info "Inštalujem cass-operator cez Helm..."
helm upgrade --install cass-operator k8ssandra/cass-operator -n cassandra \
  --set global.clusterScoped=true \
  --wait --timeout 5m

info "Aplikujem CassandraDatacenter..."
cat << 'EOF' | kubectl apply -f -
apiVersion: cassandra.datastax.com/v1beta1
kind: CassandraDatacenter
metadata:
  name: online-retail-dc1
  namespace: cassandra
spec:
  clusterName: online-retail
  serverType: cassandra
  serverVersion: "4.0.11"
  managementApiAuth:
    insecure: {}
  size: 1
  storageConfig:
    cassandraDataVolumeClaimSpec:
      storageClassName: local-path
      accessModes:
        - ReadWriteOnce
      resources:
        requests:
          storage: 20Gi
  config:
    jvm-server-options:
      initial_heap_size: "1024M"
      max_heap_size: "1024M"
EOF

info "Čakám na Cassandra pody (toto môže trvať až 5 minút)..."
kubectl wait --for=condition=ready pod -l cassandra.datastax.com/cluster=online-retail -n cassandra --timeout=300s || true

ok "Cassandra inštalácia dokončená"
