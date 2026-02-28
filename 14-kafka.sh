#!/bin/bash
set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✅ $*${NC}"; }
err()  { echo -e "${RED}❌ $*${NC}"; exit 1; }
info() { echo -e "${CYAN}ℹ️  $*${NC}"; }
step() { echo -e "\n${BOLD}═══════════════════════════════════════════${NC}"; echo -e "${BOLD}$*${NC}"; echo -e "${BOLD}═══════════════════════════════════════════${NC}"; }

step "📦 [14/16] INŠTALÁCIA KAFKA (STRIMZI)"

kubectl create namespace kafka --dry-run=client -o yaml | kubectl apply -f -

info "Pridávam Strimzi repozitár..."
helm repo add strimzi https://strimzi.io/charts/ || true
helm repo update

info "Inštalujem strimzi-kafka-operator cez Helm..."
helm upgrade --install strimzi strimzi/strimzi-kafka-operator \
  -n kafka --wait --timeout 5m

info "Aplikujem Kafka klaster..."
cat << 'EOF' | kubectl apply -f -
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  name: online-retail-combined
  namespace: kafka
spec:
  kafka:
    version: 3.4.0
    replicas: 1
    listeners:
      - name: plain
        port: 9092
        type: internal
        tls: false
      - name: tls
        port: 9093
        type: internal
        tls: true
    config:
      offsets.topic.replication.factor: 1
      transaction.state.log.replication.factor: 1
      transaction.state.log.min.isr: 1
      default.replication.factor: 1
      min.insync.replicas: 1
      inter.broker.protocol.version: "3.4"
    storage:
      type: jbod
      volumes:
      - id: 0
        type: persistent-claim
        size: 10Gi
        deleteClaim: false
        class: local-path
  zookeeper:
    replicas: 1
    storage:
      type: persistent-claim
      size: 5Gi
      deleteClaim: false
      class: local-path
  entityOperator:
    topicOperator: {}
    userOperator: {}
EOF

info "Čakám na Kafka pody..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kafka -n kafka --timeout=300s || true

ok "Kafka inštalácia dokončená"
