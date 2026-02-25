#!/bin/bash
# 1. Kontrola a zadanie tokenu
TOKEN=$1
if [ -z "$TOKEN" ]; then
    echo -n "🔑 Vlož tvoj GitHub Personal Access Token (PAT): "
    read -s TOKEN
    echo ""
fi
if [ -z "$TOKEN" ]; then
    echo "❌ CHYBA: Token je povinný!"
    exit 1
fi

# 2. Zistenie verejnej IP
PUBLIC_IP=$(curl -s -m 10 ifconfig.me || curl -s -m 10 api.ipify.org || echo "127.0.0.1")
echo "🌐 Verejná IP: $PUBLIC_IP"

# 3. Interná IP - len ak kubectl existuje
if command -v kubectl >/dev/null 2>&1 && kubectl get nodes >/dev/null 2>&1; then
    INTERNAL_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "")
    echo "🔧 Interná IP: $INTERNAL_IP"
else
    INTERNAL_IP=""
    echo "⚠️  kubectl nedostupný - INTERNAL_IP bude nastavená po inštalácii k3s"
fi

# 4. Reset YAML placeholderov - najprv obnov originály z Gitu
echo "🔄 Obnovovám YAML z Gitu..."
git fetch origin main
git checkout origin/main -- ansible/

# 5. Nahraď IP v YAML
echo "🔧 Kalibrujem konfiguráciu..."
find . -type f -name "*.yaml" -exec sed -i "s/IP_VM_ADRESA/$PUBLIC_IP/g" {} +
if [ -n "$INTERNAL_IP" ]; then
    find . -type f -name "*.yaml" -exec sed -i "s/NODE_EXPORTER_IP/$INTERNAL_IP/g" {} +
fi

# 6. Push do Gitu
echo "⬆️  Odosielam IP na GitHub..."
git config user.name "GitOps Auto-Installer"
git config user.email "gitops@auto.install"
git add ansible/
git commit -m "auto: update IP to $PUBLIC_IP" || echo "Nič na commitovanie"
git push https://ondrejnr:${TOKEN}@github.com/ondrejnr/mon.git main --force

# 7. Vytvor flux-system namespace a secret
echo "🔐 Vytváram flux-system namespace a github-pat secret..."
kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true
kubectl create secret generic github-pat \
  --from-literal=username=ondrejnr \
  --from-literal=password=${TOKEN} \
  -n flux-system \
  --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true

# 8. Spusti Docker inštalátor
echo "🚀 Spúšťam inštaláciu klastra..."
docker run --rm --privileged --net=host \
  -v /:/host \
  -v /run/systemd:/run/systemd \
  -v /etc/rancher/k3s:/etc/rancher/k3s \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e GITHUB_TOKEN="$TOKEN" \
  ondrejnr1/mon:latest
