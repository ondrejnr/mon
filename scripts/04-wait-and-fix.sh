#!/bin/bash
source /scripts/common.sh
log_section "4. ČAKANIE NA PODY A SIEŤOVÁ KALIBRÁCIA"

TARGET_IP=$(cat /tmp/target_ip)

# Čakaj na všetky pody
for i in {1..36}; do
    RUNNING=$(kubectl get pods -A --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    NOT_RUNNING=$(kubectl get pods -A --no-headers 2>/dev/null | grep -v "Running\|Completed" | grep -vc "^$" || echo "0")
    echo "  [${i}x10s] Running: $RUNNING | Nie Running: $NOT_RUNNING"

    if [ "$NOT_RUNNING" -gt 0 ]; then
        kubectl get pods -A --no-headers 2>/dev/null | grep -v "Running\|Completed" | while read ns name ready status rest; do
            if [ -n "$name" ]; then
                log_warn "Pod $ns/$name je v stave: $status"
                log_info "Logy $name:"
                kubectl logs -n $ns $name --tail=15 2>/dev/null || true
                log_info "Events $name:"
                kubectl describe pod -n $ns $name 2>/dev/null | grep -A5 "Events:" | tail -8 || true
            fi
        done
    fi

    if [ "$RUNNING" -gt 15 ] && [ "$NOT_RUNNING" -eq 0 ]; then
        log_ok "Všetky pody bežia!"
        break
    fi
    sleep 10
done

kubectl get pods -A

# Patch Ingress hostov
log_info "Patchujem Ingress hosty na $TARGET_IP..."
kubectl get ingress -A -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null | \
while read NS ING; do
    if [ -n "$NS" ] && [ -n "$ING" ]; then
        kubectl patch ingress $ING -n $NS --type='json' \
          -p="[{\"op\": \"replace\", \"path\": \"/spec/rules/0/host\", \"value\": \"$ING.$TARGET_IP.nip.io\"}]" 2>/dev/null && \
          log_ok "Ingress $NS/$ING -> $ING.$TARGET_IP.nip.io" || \
          log_warn "Ingress $NS/$ING patch zlyhal"
    fi
done

# Kontrola interných Services
log_info "Kontrolujem interné Services..."
for svc_ns in "prometheus:monitoring" "grafana:monitoring" "apache-php:lamp" "postgresql:lamp" "elasticsearch:logging" "kibana:logging"; do
    SVC=$(echo $svc_ns | cut -d: -f1)
    NS=$(echo $svc_ns | cut -d: -f2)
    if kubectl get service $SVC -n $NS >/dev/null 2>&1; then
        log_ok "Service $SVC/$NS existuje"
    else
        log_error "Service $SVC/$NS CHÝBA"
    fi
done
