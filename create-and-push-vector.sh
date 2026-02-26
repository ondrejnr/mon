echo "=== ZISKAVAM VECTOR CONFIG Z CLUSTRA ==="
kubectl get configmap vector-config -n logging -o jsonpath='{.data.vector\.yaml}' && echo ""

echo "" && echo "=== VYTVARAM SUBOR ==="
kubectl get configmap vector-config -n logging -o jsonpath='{.data.vector\.yaml}' > /home/ondrejko_gulkas/mon/vector.yaml
echo "Riadkov: $(wc -l < /home/ondrejko_gulkas/mon/vector.yaml)"
cat /home/ondrejko_gulkas/mon/vector.yaml

echo "" && echo "=== KONTROLA KUSTOMIZATION ==="
find /home/ondrejko_gulkas/mon -name "kustomization.yaml" | xargs grep -l "vector" 2>/dev/null

echo "" && echo "=== GIT PUSH ==="
cd /home/ondrejko_gulkas/mon
git add vector.yaml
git commit -m "feat: add vector.yaml extracted from cluster configmap"
git push origin main

echo "" && echo "=== ARGOCD REFRESH ==="
kubectl annotate application logging-stack -n argocd argocd.argoproj.io/refresh=hard --overwrite
sleep 8
kubectl get application logging-stack -n argocd -o jsonpath='{.status.sync.status} {.status.health.status}' && echo ""
