echo "=== PRESUNAM NA SPRAVNE MIESTO ==="
cp /home/ondrejko_gulkas/mon/vector.yaml /home/ondrejko_gulkas/mon/ansible/clusters/my-cluster/logging/vector.yaml
echo "OK: $(ls /home/ondrejko_gulkas/mon/ansible/clusters/my-cluster/logging/)"

echo "" && echo "=== KUSTOMIZATION OBSAH ==="
cat /home/ondrejko_gulkas/mon/ansible/clusters/my-cluster/logging/kustomization.yaml

echo "" && echo "=== GIT PUSH ==="
cd /home/ondrejko_gulkas/mon
git add ansible/clusters/my-cluster/logging/vector.yaml
git commit -m "fix: move vector.yaml to correct logging kustomization path"
git push origin main

echo "" && echo "=== ARGOCD REFRESH ==="
kubectl annotate application logging-stack -n argocd argocd.argoproj.io/refresh=hard --overwrite
sleep 15
kubectl get application logging-stack -n argocd -o jsonpath='{.status.sync.status} {.status.health.status}' && echo ""
kubectl get application logging-stack -n argocd -o jsonpath='{.status.conditions[0].message}' && echo ""
