#!/bin/bash
echo "═══════════════════════════════════════════════════════════════"
echo "🔄 VÝMENA FLUENTD → VECTOR V DISASTER RECOVERY"
echo "═══════════════════════════════════════════════════════════════"

cd /home/ondrejko_gulkas/mon

# 1. ZMAZANIE FLUENTD Z CLUSTRA
echo ""
echo "🔥 [1/5] MAZEM FLUENTD Z CLUSTRA"
kubectl delete daemonset fluentd -n logging --force --grace-period=0 2>/dev/null
kubectl delete serviceaccount fluentd -n logging 2>/dev/null
kubectl delete clusterrole fluentd 2>/dev/null
kubectl delete clusterrolebinding fluentd 2>/dev/null
echo "✅ Fluentd odstránený"

# 2. VYTVORENIE VECTOR MANIFESTU Z CONFIGMAP
echo ""
echo "📄 [2/5] VYTVÁRAM VECTOR MANIFEST"
cat > ansible/clusters/my-cluster/logging/vector-daemonset.yaml << 'VECTOR'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vector
  namespace: logging
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: vector
rules:
- apiGroups: [""]
  resources: ["pods", "namespaces"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vector
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: vector
subjects:
- kind: ServiceAccount
  name: vector
  namespace: logging
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: vector
  namespace: logging
spec:
  selector:
    matchLabels:
      app: vector
  template:
    metadata:
      labels:
        app: vector
    spec:
      serviceAccountName: vector
      containers:
      - name: vector
        image: timberio/vector:0.34.0-debian
        args:
        - --config
        - /etc/vector/vector.yaml
        env:
        - name: VECTOR_SELF_NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        volumeMounts:
        - name: config
          mountPath: /etc/vector/
          readOnly: true
        - name: containers
          mountPath: /var/log/containers
          readOnly: true
        - name: pods
          mountPath: /var/log/pods
          readOnly: true
        - name: docker
          mountPath: /var/lib/docker/containers
          readOnly: true
        securityContext:
          privileged: true
      volumes:
      - name: config
        configMap:
          name: vector-config
          items:
          - key: vector.yaml
            path: vector.yaml
      - name: containers
        hostPath:
          path: /var/log/containers
      - name: pods
        hostPath:
          path: /var/log/pods
      - name: docker
        hostPath:
          path: /var/lib/docker/containers
      tolerations:
      - effect: NoSchedule
        operator: Exists
VECTOR

# 3. APLIKOVANIE VECTOR DO CLUSTRA
echo ""
echo "🚀 [3/5] NASAĎUJEM VECTOR DO CLUSTRA"
kubectl apply -f ansible/clusters/my-cluster/logging/vector-daemonset.yaml

# 4. ODSTRÁNENIE FLUENTD Z DISASTER RECOVERY
echo ""
echo "🗑️ [4/5] MAZEM FLUENTD Z DISASTER RECOVERY ZÁLOHY"
rm -f disaster-recovery/logging/daemonsets.yaml
rm -f disaster-recovery/logging/serviceaccounts.yaml
rm -f disaster-recovery/clusterroles.yaml
rm -f disaster-recovery/clusterrolebindings.yaml

# 5. PRIDANIE VECTOR DO DISASTER RECOVERY
echo ""
echo "💾 [5/5] UKLADÁM VECTOR DO DISASTER RECOVERY"
mkdir -p disaster-recovery/logging/
kubectl get daemonset vector -n logging -o yaml | \
  grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > \
  disaster-recovery/logging/daemonsets.yaml
kubectl get serviceaccount vector -n logging -o yaml | \
  grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > \
  disaster-recovery/logging/serviceaccounts.yaml
kubectl get clusterrole vector -o yaml | \
  grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > \
  disaster-recovery/clusterroles.yaml
kubectl get clusterrolebinding vector -o yaml | \
  grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > \
  disaster-recovery/clusterrolebindings.yaml

# 6. GIT COMMIT
echo ""
echo "📦 UKLADÁM DO GITU"
git add ansible/clusters/my-cluster/logging/vector-daemonset.yaml
git add disaster-recovery/
git commit -m "fix: replace fluentd with vector in disaster recovery"
git push origin main

echo ""
echo "✅ HOTOVO - Vector je nasadený a v zálohách"
echo "═══════════════════════════════════════════════════════════════"
