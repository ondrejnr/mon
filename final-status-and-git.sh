#!/bin/bash
echo "=== FINÁLNY STAV VŠETKÝCH WEBOV ==="
for url in $(kubectl get ingress -A -o jsonpath='{range .items[*]}{.spec.rules[*].host}{"\n"}{end}' | sort -u); do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://$url)
  [ "$code" = "000" ] && status="❌" || status="✅"
  echo "$status $code http://$url"
done
echo ""
echo "=== STAV PODOV ==="
kubectl get pods -A | grep -vE "Running|Completed" || echo "✅ Všetky pody OK"
echo ""
echo "=== VECTOR LOG (posledných 5) ==="
kubectl logs -n logging -l app=vector --tail=5 2>/dev/null || echo "Vector nenäjdený"
echo ""
echo "=== ELASTICSEARCH INDEXY ==="
kubectl exec -n logging deployment/elasticsearch -- curl -s "http://localhost:9200/_cat/indices?v" | grep lamp
echo ""
echo "=== UKLADAM POSLEDNÉ ZMENY DO GITU ==="
cd /home/ondrejko_gulkas/mon
git add -A
git commit -m "chore: final stable state after full recovery"
git push origin main
echo "=== HOTOVO ==="
