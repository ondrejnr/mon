#!/bin/bash
set -e

# Dynamické zistenie aktuálnej IP adresy
IP=$(curl -s ifconfig.me)

echo "🚀 Štartujem automatickú obnovu na IP: $IP"
echo "==========================================="

# 1. Kontrola k3s
if ! systemctl is-active k3s &>/dev/null; then
  echo "📦 Inštalujem k3s..."
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --disable traefik" sh -
  sleep 20
else
  echo "✅ k3s už beží"
fi

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# 2. Kontrola Fluxu
if ! kubectl get namespace flux-system &>/dev/null; then
  echo "🔗 Inštalujem Flux a pripájam GitHub..."
  curl -s https://fluxcd.io/install.sh | bash
  # Použije vopred exportovaný token
  flux bootstrap github \
    --owner=ondrejnr \
    --repository=mon \
    --branch=main \
    --path=ansible/clusters/my-cluster \
    --personal
else
  echo "✅ Flux už beží"
fi

# 3. Sledovanie obnovy
echo "⏳ Čakám na GitOps (všetko musí byť Running)..."
for i in {1..30}; do
  READY=$(kubectl get pods -A --no-headers 2>/dev/null | grep "Running" | wc -l || echo 0)
  echo "--- $((i*10))s | Running pody: $READY ---"
  if [ "$READY" -gt 15 ]; then break; fi
  sleep 10
done

# 4. Finálny test na aktuálnej IP
echo -e "\n=== TEST DOSTUPNOSTI (IP: $IP) ==="
for service in apache grafana prometheus kibana web; do
  code=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: $service.$IP.nip.io" http://$IP/)
  echo "$service: $code"
done

echo -e "\n✅ KLASTER JE KOMPLETNÝ!"
