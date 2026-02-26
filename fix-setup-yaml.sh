echo "=== PRIDAVAM ALERTMANAGER DO setup.yaml ==="
cat >> /home/ondrejko_gulkas/mon/ansible/clusters/my-cluster/monitoring/setup.yaml << 'ALERTMANAGER'
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: alertmanager
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: alertmanager
  template:
    metadata:
      labels:
        app: alertmanager
    spec:
      containers:
      - name: alertmanager
        image: prom/alertmanager:latest
        ports:
        - containerPort: 9093
---
apiVersion: v1
kind: Service
metadata:
  name: alertmanager
  namespace: monitoring
spec:
  selector:
    app: alertmanager
  ports:
  - port: 9093
    targetPort: 9093
ALERTMANAGER

echo "=== FORCE RELOAD INGRESS NGINX ==="
kubectl rollout restart deployment/ingress-nginx-controller -n ingress-nginx

echo "=== GIT PUSH ==="
cd /home/ondrejko_gulkas/mon
git add ansible/clusters/my-cluster/monitoring/setup.yaml
git commit -m "fix: add alertmanager deployment+service, reload ingress"
git push origin main

echo "=== ARGOCD SYNC ==="
kubectl annotate application monitoring-stack -n argocd argocd.argoproj.io/refresh=hard --overwrite
sleep 20

echo "=== HTTP TESTY ==="
curl -s -o /dev/null -w "GRAFANA: %{http_code}\n" http://grafana.34.89.208.249.nip.io
curl -s -o /dev/null -w "ALERTMANAGER: %{http_code}\n" http://alertmanager.34.89.208.249.nip.io
curl -s -o /dev/null -w "PROMETHEUS: %{http_code}\n" http://prometheus.34.89.208.249.nip.io
curl -s -o /dev/null -w "BANKA: %{http_code}\n" http://bank.34.89.208.249.nip.io
