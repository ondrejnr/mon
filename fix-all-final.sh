echo "=== [1] INGRESS - ZRUS RESTART, PONECHAJ RUNNING POD ==="
kubectl rollout undo deployment/ingress-nginx-controller -n ingress-nginx
sleep 8 && kubectl get pods -n ingress-nginx

echo "" && echo "=== [2] MONITORING KUSTOMIZATION - EXISTUJE? ==="
ls /home/ondrejko_gulkas/mon/ansible/clusters/my-cluster/monitoring/
cat /home/ondrejko_gulkas/mon/ansible/clusters/my-cluster/monitoring/kustomization.yaml 2>/dev/null || \
echo "CHYBA: kustomization.yaml neexistuje - vytváram"
cat > /home/ondrejko_gulkas/mon/ansible/clusters/my-cluster/monitoring/kustomization.yaml << 'KUST'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- setup.yaml
KUST
cat /home/ondrejko_gulkas/mon/ansible/clusters/my-cluster/monitoring/kustomization.yaml

echo "" && echo "=== [3] BANKA - OPRAVA IMAGE PODLA MENA KONTAJNERA ==="
kubectl get deployment apache-php -n lamp -o jsonpath='{range .spec.template.spec.containers[*]}{.name}: {.image}{"\n"}{end}'
kubectl patch deployment apache-php -n lamp --type=json -p='[
  {"op":"replace","path":"/spec/template/spec/containers/3/image","value":"hipages/php-fpm_exporter:2"}
]'

echo "" && echo "=== [4] GIT PUSH ==="
cd /home/ondrejko_gulkas/mon
git add ansible/clusters/my-cluster/monitoring/kustomization.yaml
git commit -m "fix: add kustomization.yaml for monitoring-stack" 2>/dev/null || echo "nic na commitovanie"
git push origin main

echo "" && echo "=== [5] ARGOCD SYNC ==="
kubectl annotate application monitoring-stack -n argocd argocd.argoproj.io/refresh=hard --overwrite
sleep 20

echo "" && echo "=== FINALNA KONTROLA ==="
kubectl get pods -A | grep -vE "Running|Completed"
kubectl get endpoints -n monitoring
for url in bank.34.89.208.249.nip.io grafana.34.89.208.249.nip.io alertmanager.34.89.208.249.nip.io prometheus.34.89.208.249.nip.io; do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://$url)
  echo "  $code → http://$url"
done
