#!/bin/bash
set -e
echo "=== [5/7] Web (nginx) ==="
kubectl create namespace web 2>/dev/null || true
kubectl create namespace web-stack 2>/dev/null || true
# web
cat << 'WEB' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-web
  namespace: web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-web
  template:
    metadata:
      labels:
        app: nginx-web
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  namespace: web
spec:
  selector:
    app: nginx-web
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-ingress
  namespace: web
spec:
  ingressClassName: nginx
  rules:
  - host: web.34.89.208.249.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nginx-service
            port:
              number: 80
WEB
# web-stack (3 repliky)
cat << 'WEBSTACK' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-app
  namespace: web-stack
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx-app
  template:
    metadata:
      labels:
        app: nginx-app
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-balancer
  namespace: web-stack
spec:
  selector:
    app: nginx-app
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-ingress
  namespace: web-stack
spec:
  ingressClassName: nginx
  rules:
  - host: nginx.34.89.208.249.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nginx-balancer
            port:
              number: 80
WEBSTACK
echo "✅ Web nasadený."
