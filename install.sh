#!/bin/bash
# Spustenie: ./install.sh <tvoj_github_token>

TOKEN=$1
if [ -z "$TOKEN" ]; then
    echo "❌ CHYBA: Musíš zadať GitHub Token!"
    echo "Príklad: ./install.sh ghp_xxxxxxxxx"
    exit 1
fi

# 1. Zistenie aktuálnej verejnej IP adresy
PUBLIC_IP=$(curl -s ifconfig.me)
echo "🌐 Identifikovaná IP servera: $PUBLIC_IP"

# 2. Úprava lokálnych súborov (Nahradenie placeholderu realitou)
echo "🔧 Kalibrujem konfiguráciu..."
find . -type f -name "*.yaml" -exec sed -i "s/IP_VM_ADRESA/$PUBLIC_IP/g" {} +

# 3. Synchronizácia Githubu (Source of Truth fix)
echo "⬆️ Odosielam aktuálnu konfiguráciu na GitHub..."
git config user.name "GitOps Auto-Installer"
git config user.email "gitops@auto.install"
git add .
git commit -m "auto: update IP to $PUBLIC_IP for deployment"
git push https://ondrejnr:${TOKEN}@github.com/ondrejnr/mon.git main --force

# 4. Spustenie hlavného Docker inštalátora
echo "🚀 Spúšťam inštaláciu klastra..."
docker run --rm --privileged --net=host \
  -v /:/host \
  -v /run/systemd:/run/systemd \
  -v /etc/rancher/k3s:/etc/rancher/k3s \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e GITHUB_TOKEN="$TOKEN" \
  ondrejnr1/mon:latest
