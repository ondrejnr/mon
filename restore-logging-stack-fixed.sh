#!/bin/bash
set -e
echo "═══════════════════════════════════════════════════════════════"
echo "🔄 OBNOVA LOGGING STACKU (ES 7.17.10 + Kibana + Vector)"
echo "═══════════════════════════════════════════════════════════════"

NAMESPACE="logging"

# 1. Vytvorenie namespace (ak neexistuje)
kubectl create namespace $NAMESPACE 2>/dev/null || echo "Namespace $NAMESPACE už existuje"

# 2. Elasticsearch
cat << ES | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: elasticsearch
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: elasticsearch
  template:
    metadata:
      labels:
        app: elasticsearch
    spec:
      containers:
      - name: elasticsearch
        image: docker.elastic.co/elasticsearch/elasticsearch:7.17.10
        ports:
        - containerPort: 9200
        - containerPort: 9300
        env:
        - name: discovery.type
          value: single-node
        - name: xpack.security.enabled
          value: "false"
        - name: ES_JAVA_OPTS
          value: "-Xms512m -Xmx512m"
---
apiVersion: v1
kind: Service
metadata:
  name: elasticsearch
  namespace: $NAMESPACE
spec:
  selector:
    app: elasticsearch
  ports:
  - port: 9200
    targetPort: 9200
    name: http
  - port: 9300
    targetPort: 9300
    name: transport
ES

# 3. Kibana
cat << KIBANA | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kibana
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kibana
  template:
    metadata:
      labels:
        app: kibana
    spec:
      containers:
      - name: kibana
        image: docker.elastic.co/kibana/kibana:7.17.10
        ports:
        - containerPort: 5601
        env:
        - name: ELASTICSEARCH_HOSTS
          value: http://elasticsearch:9200
---
apiVersion: v1
kind: Service
metadata:
  name: kibana
  namespace: $NAMESPACE
spec:
  selector:
    app: kibana
  ports:
  - port: 5601
    targetPort: 5601
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kibana-ingress
  namespace: $NAMESPACE
spec:
  ingressClassName: nginx
  rules:
  - host: kibana.34.89.208.249.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kibana
            port:
              number: 5601
KIBANA

# 4. Počkám na Elasticsearch a Kibanu
echo "⏳ Čakám na Elasticsearch a Kibanu (60s)..."
sleep 60

# 5. Vector – najprv vytvoríme ConfigMap
cat << VECTORCM | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: vector-config
  namespace: $NAMESPACE
data:
  vector.yaml: |
    sources:
      all_logs:
        type: kubernetes_logs
        node_annotation_fields: {}
    transforms:
      simple_remap:
        type: remap
        inputs: ["all_logs"]
        source: |
          .pod_name = .kubernetes.pod_name
          .namespace = .kubernetes.pod_namespace
          .status = "repaired"
    sinks:
      es_out:
        type: elasticsearch
        inputs: ["simple_remap"]
        endpoints: ["http://elasticsearch:9200"]
        mode: "data_stream"
        data_stream:
          type: "logs"
          dataset: "lamp"
          namespace: "default"
VECTORCM

# 6. Vector DaemonSet
cat << VECTORDS | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vector
  namespace: $NAMESPACE
---
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
  namespace: $NAMESPACE
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: vector
  namespace: $NAMESPACE
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
VECTORDS

echo "⏳ Čakám na Vector (30s)..."
sleep 30

# 7. Vygenerovanie test logu
kubectl exec -n lamp deployment/apache-php -- curl -s http://localhost/ >/dev/null 2>&1 || true
sleep 10

# 8. Kontrola indexov
echo ""
echo "📊 INDEXY V ELASTICSEARCH:"
kubectl exec -n $NAMESPACE deployment/elasticsearch -- curl -s "http://localhost:9200/_cat/indices?v" | grep logs-lamp || echo "Zatiaľ žiadne indexy"

# 9. Vytvorenie index pattern v Kibane
KIBANA_URL="http://kibana.34.89.208.249.nip.io"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" $KIBANA_URL)
if [ "$HTTP_CODE" == "200" ] || [ "$HTTP_CODE" == "302" ]; then
    curl -s -X POST "$KIBANA_URL/api/saved_objects/index-pattern" \
      -H "kbn-xsrf: true" \
      -H "Content-Type: application/json" \
      -d '{"attributes":{"title":"logs-lamp-*","timeFieldName":"@timestamp"}}' && echo "✅ Index pattern vytvorený" || echo "⚠️ Index pattern sa nepodarilo vytvoriť"
else
    echo "❌ Kibana nie je dostupná (HTTP $HTTP_CODE)"
fi

echo ""
echo "✅ OBNOVA DOKONČENÁ"
echo "Kibana by mala byť dostupná na http://kibana.34.89.208.249.nip.io"
echo "Počkaj pár minút, kým sa naplnia logy, a potom v Discover vyber index pattern 'logs-lamp-*'"
echo "═══════════════════════════════════════════════════════════════"

# 10. Uloženie do Gitu (ak je repozitár)
cd /home/ondrejko_gulkas/mon 2>/dev/null || exit
mkdir -p ansible/clusters/my-cluster/logging
kubectl get deployment elasticsearch -n $NAMESPACE -o yaml | grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > ansible/clusters/my-cluster/logging/elasticsearch-deployment.yaml 2>/dev/null || true
kubectl get deployment kibana -n $NAMESPACE -o yaml | grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > ansible/clusters/my-cluster/logging/kibana-deployment.yaml 2>/dev/null || true
kubectl get configmap vector-config -n $NAMESPACE -o yaml | grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > ansible/clusters/my-cluster/logging/vector-configmap.yaml 2>/dev/null || true
kubectl get daemonset vector -n $NAMESPACE -o yaml | grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > ansible/clusters/my-cluster/logging/vector-daemonset.yaml 2>/dev/null || true
kubectl get ingress -n $NAMESPACE -o yaml | grep -v "status\|resourceVersion\|uid\|creationTimestamp\|managedFields" > ansible/clusters/my-cluster/logging/ingress.yaml 2>/dev/null || true

git add ansible/clusters/my-cluster/logging/ 2>/dev/null || true
git commit -m "fix: restore logging stack with working versions" 2>/dev/null || true
git push origin main 2>/dev/null || true
