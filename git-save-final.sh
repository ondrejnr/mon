#!/bin/bash
echo "💾 UKLADAM DO GIT - KOMPLETNY STAV"

cd /home/ondrejko_gulkas/mon

# 1. INGRESS CONTROLLER - zmena na LoadBalancer
cat > ansible/clusters/my-cluster/ingress-nginx/service-patch.yaml << 'YAML'
apiVersion: v1
kind: Service
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
spec:
  type: LoadBalancer
YAML

# 2. LOGGING - kompletny stack
mkdir -p ansible/clusters/my-cluster/logging
cat > ansible/clusters/my-cluster/logging/setup.yaml << 'YAML'
apiVersion: v1
kind: Namespace
metadata:
  name: logging
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
        image: docker.elastic.co/elasticsearch/elasticsearch:8.11.0
        ports:
        - containerPort: 9200
        - containerPort: 9300
        env:
        - name: discovery.type
          value: single-node
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
  - port: 9200
    targetPort: 9200
    name: http
  - port: 9300
    targetPort: 9300
    name: transport
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
        image: docker.elastic.co/kibana/kibana:8.11.0
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

# 3. INGRESS FIX - webhook disabled (pre prípad)
cat > disaster-recovery/ingress-webhook-fix.sh << 'FIX'
#!/bin/bash
echo "🔧 INGRESS WEBHOOK FIX"
kubectl delete validatingwebhookconfigurations ingress-nginx-admission 2>/dev/null
kubectl patch svc -n ingress-nginx ingress-nginx-controller -p '{"spec":{"type":"LoadBalancer"}}'
FIX
chmod +x disaster-recovery/ingress-webhook-fix.sh

# 4. COMMIT A PUSH
git add ansible/clusters/my-cluster/ingress-nginx/
git add ansible/clusters/my-cluster/logging/
git add disaster-recovery/
git commit -m "fix: final stable state - LoadBalancer, logging stack, webhook fix"
git push origin main

echo "✅ Všetky zmeny uložené do Gitu"
echo "📁 Adresár: /home/ondrejko_gulkas/mon/ansible/clusters/my-cluster/"
