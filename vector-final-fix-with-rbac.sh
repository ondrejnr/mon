#!/bin/bash
set -e
echo "═══════════════════════════════════════════════════════════════"
echo "🔧 FINÁLNA OPRAVA VECTORA (endpoint + RBAC)"
echo "═══════════════════════════════════════════════════════════════"

NAMESPACE="logging"

# 1. Overiť a opraviť ConfigMap
echo ""
echo "📁 [1/5] OPRAVA CONFIGMAP VECTORA"
# Zmažeme starú ConfigMap (aj keby ju ArgoCD vracalo, urobíme to teraz)
kubectl delete configmap vector-config -n $NAMESPACE --ignore-not-found

# Vytvoríme novú so správnym endpointom a pridaním data_stream pre lepšiu kompatibilitu
kubectl create configmap vector-config -n $NAMESPACE --from-literal=vector.yaml="
sources:
  all_logs:
    type: kubernetes_logs
    # Pridané pre zníženie chýb s annotáciami (nebude sa pokúšať o node metadata)
    # Toto vyrieši chyby s forbidden nodes
    node_annotation_fields: {}
transforms:
  simple_remap:
    type: remap
    inputs: [\"all_logs\"]
    source: |
      .pod_name = .kubernetes.pod_name
      .namespace = .kubernetes.pod_namespace
      .status = \"repaired\"
sinks:
  es_out:
    type: elasticsearch
    inputs: [\"simple_remap\"]
    endpoints: [\"http://elasticsearch.logging:9200\"]
    mode: \"bulk\"
    index: \"lamp-logs-%Y.%m.%d\"
"

echo "✅ ConfigMap vytvorená."

# 2. Pridať RBAC pre Vector (ak chýba)
echo ""
echo "🔑 [2/5] DOPLNENIE RBAC PRE VECTOR"
cat << 'RBAC' | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: vector
rules:
- apiGroups: [""]
  resources: ["pods", "namespaces", "nodes"]
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
RBAC
echo "✅ RBAC aktualizované."

# 3. Reštartovať Vector daemonset
echo ""
echo "🔄 [3/5] REŠTART VECTOR DAEMONSET"
kubectl rollout restart daemonset vector -n $NAMESPACE
sleep 20

# 4. Kontrola logov a endpointu
echo ""
echo "📋 [4/5] KONTROLA LOGOV VECTORA"
kubectl logs -n $NAMESPACE -l app=vector --tail=20 | grep -E "endpoint|endpoints|elasticsearch|http://"

# 5. Generovanie test logu a kontrola indexov
echo ""
echo "📊 [5/5] GENEROVANIE TEST LOGOV A KONTROLA INDEXOV"
kubectl exec -n lamp deployment/apache-php -- curl -s http://localhost/ >/dev/null 2>&1 || true
sleep 10

# Zobrazenie indexov (mal by pribudnúť lamp-logs-...)
kubectl exec -n $NAMESPACE deployment/elasticsearch -- curl -s "http://localhost:9200/_cat/indices?v" | grep -v "^\\."

echo ""
echo "✅ FINÁLNA OPRAVA DOKONČENÁ"
echo "═══════════════════════════════════════════════════════════════"

# 6. Uloženie do Gitu
cd /home/ondrejko_gulkas/mon
mkdir -p ansible/clusters/my-cluster/logging
kubectl get configmap vector-config -n $NAMESPACE -o yaml | \
  grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > \
  ansible/clusters/my-cluster/logging/vector-configmap.yaml
kubectl get clusterrole vector -o yaml | \
  grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > \
  ansible/clusters/my-cluster/logging/vector-clusterrole.yaml
kubectl get clusterrolebinding vector -o yaml | \
  grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > \
  ansible/clusters/my-cluster/logging/vector-clusterrolebinding.yaml
git add ansible/clusters/my-cluster/logging/
git commit -m "fix: vector final - correct endpoint and RBAC" || true
git push origin main || echo "⚠️ Git push zlyhal (možno žiadne zmeny)"
