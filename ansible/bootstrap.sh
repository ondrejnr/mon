#!/bin/bash
set -e

echo "🔎 Kontrola Kubernetes (k3s) služby..."
# Kontrola cez systemctl na hostiteľovi (vyžaduje mount /run/systemd)
if systemctl is-active --quiet k3s; then
    echo "✅ k3s už beží ako služba. Pokračujem v konfigurácii..."
else
    echo "⚠️ k3s nie je nainštalované. Spúšťam inštaláciu..."
    curl -sfL https://get.k3s.io | sh -s - --disable traefik
fi

# Počkáme na kubeconfig
until [ -f /etc/rancher/k3s/k3s.yaml ]; do sleep 2; done
chmod 644 /etc/rancher/k3s/k3s.yaml

echo "🔑 Nastavujem GitOps (Flux) cez SSH kľúč..."
# Vytvorenie namespace
kubectl create ns flux-system --dry-run=client -o yaml | kubectl apply -f -

# Vloženie SSH kľúča z premennej (ktorá príde z Vaultu/Dockeru)
cat << EOT | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: flux-system
  namespace: flux-system
type: Opaque
stringData:
  identity: |
$(echo "$FLUX_SSH_KEY" | sed 's/^/    /')
EOT

echo "🚀 Spúšťam synchronizáciu z GitHubu..."
# Aplikujeme existujúce komponenty Fluxu z tvojho repozitára
kubectl apply -k clusters/my-cluster/flux-system/
kubectl apply -f clusters/my-cluster/flux-system/gotk-sync.yaml

echo "✅ INŠTALÁCIA DOKONČENÁ!"
