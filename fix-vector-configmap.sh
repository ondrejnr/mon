echo "=== VYTVÁRAM VECTOR CONFIGMAP MANIFEST ==="
cat > /home/ondrejko_gulkas/mon/ansible/clusters/my-cluster/logging/vector.yaml << 'MANIFEST'
apiVersion: v1
kind: ConfigMap
metadata:
  name: vector-config
  namespace: logging
data:
  vector.yaml: |
MANIFEST

# Pridaj obsah vector configu s odsadením
kubectl get configmap vector-config -n logging -o jsonpath='{.data.vector\.yaml}' | sed 's/^/    /' >> \
  /home/ondrejko_gulkas/mon/ansible/clusters/my-cluster/logging/vector.yaml

echo "=== OBSAH MANIFESTU ==="
cat /home/ondrejko_gulkas/mon/ansible/clusters/my-cluster/logging/vector.yaml

echo "" && echo "=== GIT PUSH ==="
cd /home/ondrejko_gulkas/mon
git add ansible/clusters/my-cluster/logging/vector.yaml
git commit -m "fix: wrap vector config in ConfigMap manifest for kustomize"
git push origin main

echo "" && echo "=== ARGOCD REFRESH ==="
kubectl annotate application logging-stack -n argocd argocd.argoproj.io/refresh=hard --overwrite
sleep 15
kubectl get application logging-stack -n argocd -o jsonpath='{.status.sync.status} {.status.health.status}' && echo ""
kubectl get application logging-stack -n argocd -o jsonpath='{.status.conditions[0].message}' && echo ""
