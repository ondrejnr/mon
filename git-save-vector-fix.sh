#!/bin/bash
echo "═══════════════════════════════════════════════════════════════"
echo "💾 UKLADÁM VECTOR OPRAVY DO GIT RECOVERY"
echo "═══════════════════════════════════════════════════════════════"

cd /home/ondrejko_gulkas/mon

# 1. AKTUALIZUJEM VECTOR CONFIGMAP V ANSIBLE
echo ""
echo "📁 [1/5] AKTUALIZUJEM VECTOR CONFIGMAP V MANIFESTOCH"
mkdir -p ansible/clusters/my-cluster/logging

cat > ansible/clusters/my-cluster/logging/vector-configmap.yaml << 'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: vector-config
  namespace: logging
data:
  vector.yaml: |
    sources:
      all_logs:
        type: kubernetes_logs
    transforms:
      simple_remap:
        type: remap
        inputs: ["all_logs"]
        source: |
          .pod_name = .kubernetes.pod_name
          .status = "repaired"
    sinks:
      es_out:
        type: elasticsearch
        inputs: ["simple_remap"]
        endpoint: "http://elasticsearch.logging:9200"
YAML

# 2. AKTUALIZUJEM VECTOR DAEMONSET
echo ""
echo "📁 [2/5] AKTUALIZUJEM VECTOR DAEMONSET"
cat > ansible/clusters/my-cluster/logging/vector-daemonset.yaml << 'YAML'
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
YAML

# 3. ODSTRÁNIM FLUENTD Z RECOVERY
echo ""
echo "🗑️ [3/5] MAZEM FLUENTD Z DISASTER RECOVERY"
rm -f disaster-recovery/logging/daemonsets.yaml
rm -f disaster-recovery/logging/serviceaccounts.yaml
rm -f disaster-recovery/clusterroles.yaml
rm -f disaster-recovery/clusterrolebindings.yaml

# 4. PRIDÁM VECTOR DO DISASTER RECOVERY
echo ""
echo "💾 [4/5] UKLADÁM VECTOR DO DISASTER RECOVERY"
mkdir -p disaster-recovery/logging/

# Aktuálny stav z clusteru
kubectl get configmap vector-config -n logging -o yaml | \
  grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > \
  disaster-recovery/logging/configmaps.yaml

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

# 5. COMMIT DO GITU
echo ""
echo "📦 [5/5] UKLADÁM DO GITU"
git add ansible/clusters/my-cluster/logging/
git add disaster-recovery/
git commit -m "fix: vector config - elasticsearch endpoint fix, remove fluentd from recovery"
git push origin main

echo ""
echo "✅ VŠETKY ZMENY ULOŽENÉ DO GITU"
echo "📁 Adresáre:"
echo "  - ansible/clusters/my-cluster/logging/"
echo "  - disaster-recovery/logging/"
echo "  - disaster-recovery/clusterroles.yaml"
echo "  - disaster-recovery/clusterrolebindings.yaml"
echo "═══════════════════════════════════════════════════════════════"
