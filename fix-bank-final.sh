echo "=== KONTAJNERY V DEPLOYMENT ==="
kubectl get deployment apache-php -n lamp -o jsonpath='{range .spec.template.spec.containers[*]}{.name}: {.image}{"\n"}{end}'

echo "" && echo "=== MENIM IMAGE PODLA MENA ==="
kubectl patch deployment apache-php -n lamp --type='json' -p='[
  {"op":"replace","path":"/spec/template/spec/containers/3/image","value":"hipages/php-fpm_exporter:2"}
]'

sleep 10 && kubectl get pods -n lamp
curl -s -o /dev/null -w "BANKA: %{http_code}\n" http://bank.34.89.208.249.nip.io
