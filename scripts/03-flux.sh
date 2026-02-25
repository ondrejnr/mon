#!/bin/bash
source /scripts/common.sh
log_section "3. FLUX BOOTSTRAP"

for ns in flux-system lamp monitoring logging web-stack web storage; do
    kubectl create ns $ns --dry-run=client -o yaml | kubectl apply -f -
done

log_info "Vytváram github-pat secret..."
kubectl create secret generic github-pat \
  --from-literal=username=ondrejnr \
  --from-literal=password=${GITHUB_TOKEN} \
  -n flux-system \
  --dry-run=client -o yaml | kubectl apply -f -

if ! kubectl get deployment -n flux-system source-controller >/dev/null 2>&1; then
    log_warn "Inštalujem Flux..."
    chroot /host /bin/bash -c "curl -s https://fluxcd.io/install.sh | bash"
    chroot /host /bin/bash -c "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && flux bootstrap github \
      --owner=ondrejnr \
      --repository=mon \
      --branch=main \
      --path=ansible/clusters/my-cluster \
      --personal \
      --token-auth"
else
    log_ok "Flux beží - reconcile..."
    kubectl apply -k "https://github.com/ondrejnr/mon//ansible/clusters/my-cluster?ref=main" --force
    chroot /host /bin/bash -c "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && flux reconcile kustomization flux-system --with-source -n flux-system" || true
fi

log_info "Čakám na Flux GitRepository..."
for i in {1..30}; do
    GIT_READY=$(kubectl get gitrepository flux-system -n flux-system \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
    GIT_MSG=$(kubectl get gitrepository flux-system -n flux-system \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null || echo "")
    if [ "$GIT_READY" = "True" ]; then
        log_ok "GitRepository Ready"
        break
    fi
    log_info "[${i}0s] GitRepository: $GIT_READY - $GIT_MSG"
    if echo "$GIT_MSG" | grep -q "ssh\|identity"; then
        log_warn "SSH chyba! Prepínam na HTTPS..."
        kubectl patch gitrepository flux-system -n flux-system --type='merge' -p \
          '{"spec":{"url":"https://github.com/ondrejnr/mon","secretRef":{"name":"github-pat"}}}'
    fi
    sleep 10
done

log_info "Čakám na Flux Kustomization..."
for i in {1..30}; do
    KS_READY=$(kubectl get kustomization flux-system -n flux-system \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
    KS_REV=$(kubectl get kustomization flux-system -n flux-system \
      -o jsonpath='{.status.lastAppliedRevision}' 2>/dev/null || echo "")
    if [ "$KS_READY" = "True" ]; then
        log_ok "Kustomization Ready: $KS_REV"
        break
    fi
    log_info "[${i}0s] Kustomization: $KS_READY"
    sleep 10
done
