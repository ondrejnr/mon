#!/bin/bash
source /scripts/common.sh 2>/dev/null
log_section "6. ZDRAVOTNÁ KONTROLA"

TARGET_IP=$(cat /tmp/target_ip)
PROMETHEUS_OK=false
ALL_HTTP_OK=true

# Prometheus targets
log_info "Čakám 40s na prvý scrape..."
sleep 40

for attempt in {1..5}; do
    log_info "Pokus $attempt/5 - Prometheus targets..."
    TARGETS=$(kubectl exec -n monitoring deployment/prometheus -- \
      wget -qO- "http://localhost:9090/api/v1/targets" 2>/dev/null || echo "")

    if [ -n "$TARGETS" ]; then
        RESULT=$(echo "$TARGETS" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    targets = data['data']['activeTargets']
    down = []
    for t in targets:
        job = t['labels']['job']
        health = t['health']
        url = t['scrapeUrl']
        icon = '✅' if health == 'up' else '❌'
        print(f'  {icon} {job}: {health} - {url}')
        if health != 'up':
            err = t.get('lastError', 'unknown')
            print(f'     Chyba: {err}')
            down.append(job)
    print('ALL_UP' if not down else f'DOWN:{down}')
except Exception as e:
    print(f'ERROR:{e}')
" 2>/dev/null)
        echo "$RESULT"
        if echo "$RESULT" | grep -q "ALL_UP"; then
            log_ok "Všetky Prometheus targety UP!"
            PROMETHEUS_OK=true
            break
        else
            log_warn "Niektoré targety DOWN - reštartujem Prometheus..."
            kubectl rollout restart deployment prometheus -n monitoring
            sleep 30
        fi
    else
        log_warn "Prometheus API nedostupné, čakám 20s..."
        sleep 20
    fi
done

# HTTP test
log_info "HTTP test všetkých služieb..."
declare -A SERVICES=(
    ["apache"]="apache-ingress"
    ["grafana"]="grafana-ingress"
    ["prometheus"]="prometheus-ingress"
    ["kibana"]="kibana-ingress"
    ["web"]="nginx-ingress"
)

for name in "${!SERVICES[@]}"; do
    ing="${SERVICES[$name]}"
    HOST="$ing.$TARGET_IP.nip.io"
    CODE=$(check_http "http://$TARGET_IP/" "$HOST")
    if [ "$CODE" = "200" ] || [ "$CODE" = "302" ] || [ "$CODE" = "301" ]; then
        log_ok "$name: HTTP $CODE -> http://$HOST"
    else
        log_error "$name: HTTP $CODE -> http://$HOST"
        ALL_HTTP_OK=false
    fi
done

# Záverečný report
log_section "ZÁVEREČNÝ REPORT"
echo ""
echo "  📊 Pody:"
kubectl get pods -A --no-headers | awk '{printf "  %-15s %-40s %-10s\n", $1, $2, $4}'
echo ""
echo "  🌐 URL:"
kubectl get ingress -A -o jsonpath='{range .items[*]}{"  👉 http://"}{.spec.rules[0].host}{"\n"}{end}' 2>/dev/null
echo ""
echo "  🔄 Flux:"
kubectl get gitrepository,kustomization -n flux-system 2>/dev/null || true
echo ""

if [ "$PROMETHEUS_OK" = true ] && [ "$ALL_HTTP_OK" = true ]; then
    echo "  🎉 SYSTÉM JE PLNE FUNKČNÝ!"
else
    echo "  ⚠️  SYSTÉM BEŽÍ S CHYBAMI - skontroluj logy vyššie"
fi
echo "═══════════════════════════════════════════════════════"
