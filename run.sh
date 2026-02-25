#!/bin/bash
set -e
PUBLIC_IP=$(curl -s ifconfig.me)
echo "🌐 Inštalácia na IP: $PUBLIC_IP"

# 1. Kontrola k3s (cez systemd hostiteľa)
if systemctl is-active --quiet k3s; then
    echo "✅ k3s už beží."
else
    echo "⚠️ Inštalujem k3s..."
    curl -sfL https://get.k3s.io | sh -s - --disable traefik
fi

# 2. Nastavenie prístupu
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
until [ -f $KUBECONFIG ]; do sleep 2; done

# 3. GitOps - Nasadenie z tvojho verejného GitHubu
echo "🚚 Sťahujem konfiguráciu..."
kubectl apply -k https://github.com/ondrejnr/mon//ansible/clusters/my-cluster?ref=main

# 4. Automatická oprava IP adresy pre Ingress
kubectl patch ingress apache-ingress -n lamp --type='json' -p="[{\"op\": \"replace\", \"path\": \"/spec/rules/0/host\", \"value\": \"apache.$PUBLIC_IP.nip.io\"}]" 2>/dev/null || true

echo "✅ HOTOVO!"
echo "👉 http://apache.$PUBLIC_IP.nip.io"
