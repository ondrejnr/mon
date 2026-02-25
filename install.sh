#!/bin/bash
# 1. Kontrola a zadanie tokenu
TOKEN=$1
if [ -z "$TOKEN" ]; then
    echo -n "🔑 Vlož tvoj GitHub Personal Access Token (PAT): "
    read -s TOKEN
    echo "" # Nový riadok po skrytom vstupe
fi
if [ -z "$TOKEN" ]; then
    echo "❌ CHYBA: Token je povinný pre synchronizáciu s GitHubom!"
    exit 1
fi
# 2. Zistenie aktuálnej verejnej IP adresy
PUBLIC_IP=$(curl -s ifconfig.me)
echo "🌐 Identifikovaná IP servera: $PUBLIC_IP"
# 3. Úprava lokálnych súborov (Nahradenie placeholderu realitou)
echo "🔧 Kalibrujem konfiguráciu v YAML súboroch..."
find . -type f -name "*.yaml" -exec sed -i "s/IP_VM_ADRESA/$PUBLIC_IP/g" {} +
# 4. Synchronizácia GitHubu (Zápis aktuálnej IP do Zdroja pravdy)
echo "⬆️ Odosielam novú IP adresu na GitHub..."
git config user.name "GitOps Auto-Installer"
git config user.email "gitops@auto.install"
git add .
git commit -m "auto: update IP to $PUBLIC_IP for deployment"
# Použijeme token pre autentifikáciu v URL
git push https://ondrejnr:${TOKEN}@github.com/ondrejnr/mon.git main --force
# 5. Vytvorenie github-pat secretu pre Flux
echo "🔐 Vytváram github-pat secret pre Flux..."
kubectl create secret generic github-pat \
  --from-literal=username=ondrejnr \
  --from-literal=password=${TOKEN} \
  -n flux-system \
  --dry-run=client -o yaml | kubectl apply -f -
# 6. Spustenie hlavného Docker inštalátora
echo "🚀 Spúšťam inštaláciu klastra..."
docker run --rm --privileged --net=host \
  -v /:/host \
  -v /run/systemd:/run/systemd \
  -v /etc/rancher/k3s:/etc/rancher/k3s \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e GITHUB_TOKEN="$TOKEN" \
  ondrejnr1/mon:latest
