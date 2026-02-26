echo "=== ARGOCD LOGGING APP CHYBA ==="
kubectl get application logging-stack -n argocd -o jsonpath='{.status.conditions}' | python3 -m json.tool 2>/dev/null

echo "" && echo "=== KUSTOMIZATION OBSAH V REPO ==="
find /home/ondrejko_gulkas/mon -name "kustomization.yaml" | while read f; do echo "--- $f ---"; cat "$f"; done

echo "" && echo "=== VECTOR.YAML EXISTUJE? ==="
ls -la /home/ondrejko_gulkas/mon/vector.yaml
head -5 /home/ondrejko_gulkas/mon/vector.yaml

echo "" && echo "=== GIT LOG ==="
cd /home/ondrejko_gulkas/mon && git log --oneline -5

echo "" && echo "=== FORCE REFRESH + SYNC ==="
kubectl patch application logging-stack -n argocd --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
kubectl annotate application logging-stack -n argocd argocd.argoproj.io/refresh=hard --overwrite
sleep 15
kubectl get application logging-stack -n argocd -o jsonpath='{.status.sync.status} {.status.health.status}' && echo ""
kubectl get application logging-stack -n argocd -o jsonpath='{.status.conditions[0].message}' && echo ""
