echo "=== OPRAVA GRAFANA PORTU V GIT ==="
sed -i 's/number: 80/number: 3000/' \
  /home/ondrejko_gulkas/mon/ansible/clusters/my-cluster/monitoring/setup.yaml
grep -A3 "grafana-ingress" /home/ondrejko_gulkas/mon/ansible/clusters/my-cluster/monitoring/setup.yaml | grep number

echo "" && echo "=== BANKA - OPRAVA IMAGE V GIT ==="
find /home/ondrejko_gulkas/mon -name "*.yaml" | xargs grep -l "php-fpm-exporter" 2>/dev/null
BANKAYAML=$(find /home/ondrejko_gulkas/mon/k8s-manifests -name "apache-php*.yaml" | tail -1)
echo "Súbor: $BANKAYAML"
sed -i 's|bitnami/php-fpm-exporter:latest|hipages/php-fpm_exporter:2|g' $BANKAYAML
grep "php-fpm" $BANKAYAML

echo "" && echo "=== CAKAM NA NOVY BANKA POD ==="
sleep 20 && kubectl get pods -n lamp

echo "" && echo "=== GIT PUSH ==="
cd /home/ondrejko_gulkas/mon
git add -A
git commit -m "fix: grafana ingress port 3000, phpfpm-exporter correct image"
git push origin main

echo "" && echo "=== ARGOCD REFRESH ==="
kubectl annotate application monitoring-stack -n argocd argocd.argoproj.io/refresh=hard --overwrite
kubectl annotate application lamp-stack -n argocd argocd.argoproj.io/refresh=hard --overwrite
sleep 15

echo "" && echo "=== FINALNE HTTP TESTY ==="
for url in bank.34.89.208.249.nip.io grafana.34.89.208.249.nip.io alertmanager.34.89.208.249.nip.io prometheus.34.89.208.249.nip.io argocd.34.89.208.249.nip.io; do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://$url)
  echo "  $code → http://$url"
done
