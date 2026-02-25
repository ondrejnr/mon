#!/bin/bash
set -e
echo "======================================================="
echo "🔍 INTELIGENTNÝ SIEŤOVÝ PRIESKUM A INŠTALÁCIA"
echo "======================================================="

# 1. ZISTENIE VEREJNEJ IP
HOST_IP=$(curl -s -m 5 ifconfig.me || echo "127.0.0.1")
echo "🌐 Verejná IP stroja: $HOST_IP"

# 2. KONTROLA KUBERNETES
export KUBECONFIG=/host/etc/rancher/k3s/k3s.yaml
if [ -f /host/usr/local/bin/k3s ]; then
    echo "✅ Kubernetes (k3s) nájdený."
else
    echo "⚠️ Inštalujem k3s..."
    chroot /host /bin/bash -c "curl -sfL https://get.k3s.io | sh -s - --disable traefik"
fi

until [ -f $KUBECONFIG ] && kubectl get nodes >/dev/null 2>&1; do
    echo "🔄 Čakám na Kubernetes API..."
    sleep 5
done
echo "✅ Kubernetes API je pripravený"

# 3. TRAEFIK - ak nebeží, nasaď ho
if ! kubectl get deployment traefik -n kube-system >/dev/null 2>&1; then
    echo "⚠️ Inštalujem Traefik..."
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
else
    echo "✅ Traefik už beží"
fi

# 4. FLUX - ak nebeží, nasaď ho
if ! kubectl get namespace flux-system >/dev/null 2>&1; then
    echo "⚠️ Inštalujem Flux..."
    chroot /host /bin/bash -c "curl -s https://fluxcd.io/install.sh | bash"
    chroot /host /bin/bash -c "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && flux bootstrap github \
      --owner=ondrejnr \
      --repository=mon \
      --branch=main \
      --path=ansible/clusters/my-cluster \
      --personal"
else
    echo "✅ Flux už beží"
fi

# 5. ZISTENIE IP
LB_IP=$(kubectl get svc -n kube-system traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
TARGET_IP=${LB_IP:-$HOST_IP}
echo "📍 Cieľová IP: $TARGET_IP"

# 6. CAKAJ NA GITOPS
echo "⏳ Čakám na GitOps obnovu..."
for i in {1..24}; do
    sleep 15
    RUNNING=$(kubectl get pods -A --no-headers 2>/dev/null | grep "Running" | wc -l)
    echo "[$((i*15))s] Running podov: $RUNNING"
    if [ "$RUNNING" -gt 15 ]; then
        echo "✅ Cluster obnovený!"
        break
    fi
done

# 7. FINALNY TEST
echo ""
echo "======================================================="
echo "🎉 SYSTÉM JE KONFIGUROVANÝ"
echo "======================================================="
curl -s -o /dev/null -w "apache:      %{http_code}\n" -H "Host: apache.$TARGET_IP.nip.io" http://$TARGET_IP/
curl -s -o /dev/null -w "grafana:     %{http_code}\n" -H "Host: grafana.$TARGET_IP.nip.io" http://$TARGET_IP/
curl -s -o /dev/null -w "prometheus:  %{http_code}\n" -H "Host: prometheus.$TARGET_IP.nip.io" http://$TARGET_IP/
curl -s -o /dev/null -w "kibana:      %{http_code}\n" -H "Host: kibana.$TARGET_IP.nip.io" http://$TARGET_IP/
curl -s -o /dev/null -w "web:         %{http_code}\n" -H "Host: web.$TARGET_IP.nip.io" http://$TARGET_IP/

echo ""
kubectl get ingress -A
echo "======================================================="
