echo "=== PRIDAVAM ELASTICSEARCH DO LOGGING SETUP ==="
cat >> /home/ondrejko_gulkas/mon/ansible/clusters/my-cluster/logging/setup.yaml << 'ES'
---
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
        image: elasticsearch:7.17.10
        ports:
        - containerPort: 9200
        - containerPort: 9300
        env:
        - name: discovery.type
          value: single-node
        - name: ES_JAVA_OPTS
          value: "-Xms512m -Xmx512m"
        - name: xpack.security.enabled
          value: "false"
ES

echo "=== GIT PUSH ==="
cd /home/ondrejko_gulkas/mon
git add ansible/clusters/my-cluster/logging/setup.yaml
git commit -m "fix: add elasticsearch deployment to logging stack"
git push origin main

echo "=== ARGOCD REFRESH ==="
kubectl annotate application logging-stack -n argocd argocd.argoproj.io/refresh=hard --overwrite
sleep 30

echo "=== ELASTICSEARCH POD ==="
kubectl get pods -n logging

echo "=== CAKAM AZ ELASTICSEARCH NASTARTUJE (max 60s) ==="
kubectl wait --for=condition=ready pod -l app=elasticsearch -n logging --timeout=60s 2>/dev/null || \
kubectl get pods -n logging

sleep 10
curl -s -o /dev/null -w "KIBANA: %{http_code}\n" http://kibana.34.89.208.249.nip.io
