echo "=== GIT ADD ALL + COMMIT ==="
cd /home/ondrejko_gulkas/mon
git add -A
git commit -m "chore: track all scripts and cleanup files"
git push origin main

echo "" && echo "=== ARGOCD REFRESH ==="
kubectl annotate application monitoring-stack -n argocd argocd.argoproj.io/refresh=hard --overwrite
sleep 15
kubectl get applications -A -o custom-columns="NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status"
