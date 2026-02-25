#!/bin/bash
source /scripts/common.sh
log_section "1. KUBERNETES"

PUBLIC_IP=$(curl -s -m 10 ifconfig.me || curl -s -m 10 api.ipify.org || echo "127.0.0.1")
echo $PUBLIC_IP > /tmp/public_ip
log_ok "Verejná IP: $PUBLIC_IP"

if chroot /host systemctl is-active --quiet k3s 2>/dev/null; then
    log_ok "k3s beží ako systemd služba"
elif [ -f /host/usr/local/bin/k3s ]; then
    log_ok "k3s je nainštalovaný ako binárka"
else
    log_warn "Kubernetes chýba. Inštalujem k3s..."
    chroot /host /bin/bash -c "curl -sfL https://get.k3s.io | sh -s - --disable traefik"
    until [ -f $KUBECONFIG ]; do
        log_info "Čakám na k3s konfig..."
        sleep 5
    done
fi

log_info "Čakám na Kubernetes API..."
until kubectl get nodes >/dev/null 2>&1; do sleep 5; done
log_ok "Kubernetes API je pripravený"

INTERNAL_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "")
echo $INTERNAL_IP > /tmp/internal_ip
log_ok "Interná IP uzla: $INTERNAL_IP"
kubectl get nodes -o wide
