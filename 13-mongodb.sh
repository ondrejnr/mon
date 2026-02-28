#!/bin/bash
set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✅ $*${NC}"; }
err()  { echo -e "${RED}❌ $*${NC}"; exit 1; }
info() { echo -e "${CYAN}ℹ️  $*${NC}"; }
step() { echo -e "\n${BOLD}═══════════════════════════════════════════${NC}"; echo -e "${BOLD}$*${NC}"; echo -e "${BOLD}═══════════════════════════════════════════${NC}"; }

step "📦 [13/16] INŠTALÁCIA MONGODB"

kubectl create namespace mongodb --dry-run=client -o yaml | kubectl apply -f -

info "Pridávam Percona repozitár..."
helm repo add percona https://percona.github.io/percona-helm-charts/ || true
helm repo update

info "Inštalujem percona-operator-psmdb-operator cez Helm..."
helm upgrade --install percona-operator percona/psmdb-operator \
  -n mongodb --wait --timeout 5m

info "Aplikujem PerconaServerMongoDB klaster..."
cat << 'EOF' | kubectl apply -f -
apiVersion: psmdb.percona.com/v1-12-0
kind: PerconaServerMongoDB
metadata:
  name: online-retail
  namespace: mongodb
spec:
  crVersion: 1.12.0
  image: percona/percona-server-mongodb:5.0.14-12
  allowUnsafeConfigurations: false
  secrets:
    users: mongodb-secret
  replsets:
  - name: rs0
    size: 1
    volumeSpec:
      persistentVolumeClaim:
        accessModes: [ "ReadWriteOnce" ]
        resources:
          requests:
            storage: 20Gi
        storageClassName: local-path
EOF

info "Čakám na MongoDB pody..."
kubectl wait --for=condition=ready pod -l app=percona-server-mongodb -n mongodb --timeout=300s || true

ok "MongoDB inštalácia dokončená"
