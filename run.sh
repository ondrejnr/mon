#!/bin/bash
set -e
echo "======================================================="
echo "🔍 INTELIGENTNÝ PRIESKUM A AUTO-INŠTALÁCIA"
echo "======================================================="

# 1. IDENTIFIKÁCIA IP ADRESY
PUBLIC_IP=$(curl -s -m 5 ifconfig.me || echo "127.0.0.1")
echo "🌐 Verejná IP stroja: $PUBLIC_IP"

# 2. KONTROLA KUBERNETES
export KUBECONFIG=/host/etc/rancher/k3s/k3s.yaml
if chroot /host systemctl is-active --quiet k3s 2>/dev/null; then
    echo "✅ Zistené: k3s beží ako systemd služba."
elif [ -f /host/usr/local/bin/k3s ]; then
    echo "✅ Zistené: k3s je nainštalovaný ako binárka."
else
    echo "⚠️ Kubernetes chýba. Inštalujem k3s..."
    chroot /host /bin/bash -c "curl -sfL https://get.k3s.io | sh -s - --disable traefik"
    until [ -f $KUBECONFIG ]; do sleep 5; done
fi

# Počkáme na API
until kubectl get nodes >/dev/null 2>&1; do
    echo "🔄 Čakám na Kubernetes API..."
    sleep 5
done
echo "✅ Kubernetes API je pripravený"

# 3. TRAEFIK - VZDY PRED GITOPS
echo "🔧 Nasadzujem Traefik..."
kubectl apply -f - <<TRAEFIK
apiVersion: v1
kind: ServiceAccount
metadata:
  name: traefik
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: traefik
rules:
- apiGroups: [""]
  resources: ["services","endpoints","secrets"]
  verbs: ["get","list","watch"]
- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses","ingressclasses"]
  verbs: ["get","list","watch"]
- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses/status"]
  verbs: ["update"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: traefik
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: traefik
subjects:
- kind: ServiceAccount
  name: traefik
  namespace: kube-system
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: traefik
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: traefik
  template:
    metadata:
      labels:
        app: traefik
    spec:
      serviceAccountName: traefik
      containers:
      - name: traefik
        image: traefik:v2.10
        args:
        - --providers.kubernetesingress
        - --entrypoints.web.address=:80
        - --entrypoints.websecure.address=:443
        ports:
        - name: web
          containerPort: 80
        - name: websecure
          containerPort: 443
---
apiVersion: v1
kind: Service
metadata:
  name: traefik
  namespace: kube-system
spec:
  selector:
    app: traefik
  ports:
  - name: web
    port: 80
    targetPort: 80
  - name: websecure
    port: 443
    targetPort: 443
  type: LoadBalancer
---
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: traefik
spec:
  controller: traefik.io/ingress-controller
TRAEFIK

echo "⏳ Čakám na Traefik..."
kubectl rollout status deployment/traefik -n kube-system --timeout=120s
echo "✅ Traefik beží"

# 4. GITOPS - FLUX BOOTSTRAP alebo SYNC
echo "🚚 Sťahujem konfiguráciu z GitHub (ondrejnr/mon)..."

# Vytvoríme namespacey dopredu
for ns in flux-system lamp monitoring logging web-stack web storage; do
    kubectl create ns $ns --dry-run=client -o yaml | kubectl apply -f -
done

# Vytvoríme github-pat secret PRED bootstrapom
echo "🔐 Vytváram github-pat secret pre Flux..."
kubectl create secret generic github-pat \
  --from-literal=username=ondrejnr \
  --from-literal=password=${GITHUB_TOKEN} \
  -n flux-system \
  --dry-run=client -o yaml | kubectl apply -f -

if ! kubectl get namespace flux-system >/dev/null 2>&1 || ! kubectl get deployment -n flux-system source-controller >/dev/null 2>&1; then
    echo "⚠️ Inštalujem Flux..."
    chroot /host /bin/bash -c "curl -s https://fluxcd.io/install.sh | bash"
    chroot /host /bin/bash -c "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && flux bootstrap github \
      --owner=ondrejnr \
      --repository=mon \
      --branch=main \
      --path=ansible/clusters/my-cluster \
      --personal \
      --token-auth"
else
    echo "✅ Flux beží - aplikujem GitOps priamo..."
    kubectl apply -k "https://github.com/ondrejnr/mon//ansible/clusters/my-cluster?ref=main" --force
    chroot /host /bin/bash -c "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && flux reconcile kustomization flux-system --with-source -n flux-system" || true
fi

# 5. CAKAJ NA GITOPS OBNOVU
echo "⏳ Čakám na GitOps obnovu..."
for i in {1..24}; do
    sleep 15
    RUNNING=$(kubectl get pods -A --no-headers 2>/dev/null | grep "Running" | wc -l)
    NOT_RUNNING=$(kubectl get pods -A --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l)
    echo "[$((i*15))s] Running: $RUNNING | Nie Running: $NOT_RUNNING"
    if [ "$RUNNING" -gt 15 ] && [ "$NOT_RUNNING" -eq 0 ]; then
        echo "✅ Cluster plne obnovený!"
        break
    fi
done

# 6. AUTO-DETEKCIA A MAPOVANIE SLUŽIEB
echo "🕵️ Detegujem aktívne služby pre sieťové prepojenie..."
sleep 10

LB_IP=$(kubectl get svc -n kube-system traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
TARGET_IP=${LB_IP:-$PUBLIC_IP}
echo "📍 Cieľová IP: $TARGET_IP"

INGRESSES=$(kubectl get ingress -A -o jsonpath='{.items[*].metadata.name}')
for ing in $INGRESSES; do
    NS=$(kubectl get ingress -A | grep "$ing " | awk '{print $1}')
    echo "🔗 Prepájam: $ing (Namespace: $NS) -> http://$ing.$TARGET_IP.nip.io"
    kubectl patch ingress $ing -n $NS --type='json' \
      -p="[{\"op\": \"replace\", \"path\": \"/spec/rules/0/host\", \"value\": \"$ing.$TARGET_IP.nip.io\"}]" 2>/dev/null || true
done

# 7. FINALNY TEST
echo ""
echo "======================================================="
echo "✅ SYSTÉM JE ONLINE A SKALIBROVANÝ!"
echo "======================================================="
curl -s -o /dev/null -w "apache:      %{http_code}\n" -H "Host: apache.$TARGET_IP.nip.io" http://$TARGET_IP/
curl -s -o /dev/null -w "grafana:     %{http_code}\n" -H "Host: grafana.$TARGET_IP.nip.io" http://$TARGET_IP/
curl -s -o /dev/null -w "prometheus:  %{http_code}\n" -H "Host: prometheus.$TARGET_IP.nip.io" http://$TARGET_IP/
curl -s -o /dev/null -w "kibana:      %{http_code}\n" -H "Host: kibana.$TARGET_IP.nip.io" http://$TARGET_IP/
curl -s -o /dev/null -w "web:         %{http_code}\n" -H "Host: web.$TARGET_IP.nip.io" http://$TARGET_IP/

echo ""
kubectl get ingress -A | grep nip.io | awk '{print "👉 http://"$3}'
echo "======================================================="
