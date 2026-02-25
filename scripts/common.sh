#!/bin/bash
# Spoločné funkcie pre všetky skripty

export KUBECONFIG=/host/etc/rancher/k3s/k3s.yaml
export ERRORS=0

log_info()    { echo "ℹ️  [$(date '+%H:%M:%S')] $1"; }
log_ok()      { echo "✅ [$(date '+%H:%M:%S')] $1"; }
log_warn()    { echo "⚠️  [$(date '+%H:%M:%S')] $1"; }
log_error()   { echo "❌ [$(date '+%H:%M:%S')] $1"; ERRORS=$((ERRORS+1)); }
log_section() { echo ""; echo "═══════════════════════════════════════════════════════"; echo "  🔷 $1"; echo "═══════════════════════════════════════════════════════"; }

wait_for_deployment() {
    local name=$1 ns=$2 timeout=${3:-180}
    log_info "Čakám na deployment $name/$ns..."
    for i in $(seq 1 $((timeout/10))); do
        READY=$(kubectl get deployment $name -n $ns -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        DESIRED=$(kubectl get deployment $name -n $ns -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
        if [ "${READY:-0}" -ge "${DESIRED:-1}" ]; then
            log_ok "$name Ready ($READY/$DESIRED)"
            return 0
        fi
        echo "  [${i}0s] $name: ${READY:-0}/$DESIRED Ready"
        CRASH=$(kubectl get pods -n $ns -l app=$name --no-headers 2>/dev/null | grep -c "CrashLoop\|Error\|OOMKilled" || true)
        if [ "$CRASH" -gt 0 ]; then
            log_warn "Pod $name crashuje! Logy:"
            kubectl logs -n $ns -l app=$name --tail=20 2>/dev/null || true
        fi
        sleep 10
    done
    log_error "$name timeout po ${timeout}s"
    kubectl describe deployment $name -n $ns 2>/dev/null | tail -20
    return 1
}

wait_for_pod() {
    local label=$1 ns=$2 timeout=${3:-120}
    log_info "Čakám na pod $label/$ns..."
    for i in $(seq 1 $((timeout/10))); do
        STATUS=$(kubectl get pods -n $ns -l $label --no-headers 2>/dev/null | awk '{print $3}' | head -1)
        if [ "$STATUS" = "Running" ]; then
            log_ok "Pod $label Running"
            return 0
        fi
        echo "  [${i}0s] $label status: ${STATUS:-Pending}"
        if echo "$STATUS" | grep -q "CrashLoop\|Error\|OOMKilled"; then
            log_warn "Pod crashuje! Logy:"
            kubectl logs -n $ns -l $label --tail=30 2>/dev/null || true
            log_info "Reštartujem pod..."
            kubectl delete pod -n $ns -l $label 2>/dev/null || true
        fi
        sleep 10
    done
    log_error "Pod $label timeout"
    kubectl describe pod -n $ns -l $label 2>/dev/null | tail -30
    return 1
}

check_http() {
    local url=$1 host=$2
    curl -s -o /dev/null -w "%{http_code}" -m 10 -H "Host: $host" "$url" 2>/dev/null || echo "000"
}

export -f log_info log_ok log_warn log_error log_section wait_for_deployment wait_for_pod check_http
