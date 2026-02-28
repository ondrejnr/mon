#!/bin/bash
set -euo pipefail
GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✅ $*${NC}"; }
info() { echo -e "${CYAN}ℹ️  $*${NC}"; }
step() { echo -e "\n${BOLD}═══════════════════════════════════════════${NC}"; echo -e "${BOLD}$*${NC}"; echo -e "${BOLD}═══════════════════════════════════════════${NC}"; }

step "📋 [4/9] LOGGING STACK (Elasticsearch 7.17.10 + Kibana + Vector)"

kubectl apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: elasticsearch
  namespace: logging
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
  namespace: logging
spec:
  selector:
    app: elasticsearch
  ports:
  - name: http
    port: 9200
    targetPort: 9200
  - name: transport
    port: 9300
    targetPort: 9300
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kibana
  namespace: logging
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
  namespace: logging
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
  namespace: logging
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
YAML

kubectl apply -f - <<'YAML'
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
YAML

kubectl apply -f - <<'YAML'
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
        endpoints: ["http://elasticsearch.logging:9200"]
        mode: "bulk"
        index: "lamp-logs-%Y.%m.%d"
YAML

kubectl apply -f - <<'YAML'
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

info "Čakám na Elasticsearch a Kibanu (90s)..."
sleep 90
kubectl wait --for=condition=ready pod -l app=elasticsearch -n logging --timeout=120s 2>/dev/null || true
kubectl wait --for=condition=ready pod -l app=kibana -n logging --timeout=60s 2>/dev/null || true

ok "Logging stack nasadený"
kubectl get pods -n logging
