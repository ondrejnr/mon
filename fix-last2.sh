echo "=== GRAFANA - INGRESS NGINX AKTUALNY CONFIG ==="
kubectl exec -n ingress-nginx deployment/ingress-nginx-controller -- \
  bash -c "cat /etc/nginx/nginx.conf | grep -A3 'grafana'" 2>/dev/null | grep "service_port\|upstream"

echo "" && echo "=== GRAFANA INGRESS PORT V K8S ==="
kubectl get ingress grafana-ingress -n monitoring -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.port.number}' && echo ""

echo "" && echo "=== FORCE GRAFANA INGRESS NA PORT 3000 ==="
kubectl patch ingress grafana-ingress -n monitoring --type=json \
  -p='[{"op":"replace","path":"/spec/rules/0/http/paths/0/backend/service/port/number","value":3000}]'
sleep 5
curl -s -o /dev/null -w "GRAFANA po patchi: %{http_code}\n" http://grafana.34.89.208.249.nip.io

echo "" && echo "=== BANKA - PRESNY INDEX KONTAJNEROV ==="
kubectl get deployment apache-php -n lamp -o json | \
  python3 -c "import json,sys; d=json.load(sys.stdin); [print(f'{i}: {c[\"name\"]} → {c[\"image\"]}') for i,c in enumerate(d['spec']['template']['spec']['containers'])]"

echo "" && echo "=== PATCH PODLA INDEXU ==="
# Najdeme index phpfpm-exporter a patchneme
IDX=$(kubectl get deployment apache-php -n lamp -o json | \
  python3 -c "import json,sys; d=json.load(sys.stdin); [print(i) for i,c in enumerate(d['spec']['template']['spec']['containers']) if 'phpfpm-exporter' in c['name'] or 'php-fpm-exporter' in c['name']]")
echo "Index phpfpm-exporter kontajnera: $IDX"
kubectl patch deployment apache-php -n lamp --type=json \
  -p="[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/${IDX}/image\",\"value\":\"hipages/php-fpm_exporter:2\"}]"

sleep 15
echo "" && echo "=== FINALNE HTTP TESTY ==="
for url in bank.34.89.208.249.nip.io grafana.34.89.208.249.nip.io alertmanager.34.89.208.249.nip.io prometheus.34.89.208.249.nip.io; do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://$url)
  echo "  $code → http://$url"
done
