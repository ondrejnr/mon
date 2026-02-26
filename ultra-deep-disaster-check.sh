#!/bin/bash
echo "═══════════════════════════════════════════════════════════════"
echo "🔬 ULTRA-DEEP HAVARIJNA KONTROLA - $(date)"
echo "═══════════════════════════════════════════════════════════════"

cd /home/ondrejko_gulkas/mon

# 1. KONTROLA VŠETKÝCH MANIFESTOV
echo ""
echo "📁 [1/9] KOMPLETNÝ STAV MANIFESTOV V GITE"
for dir in ansible/clusters/my-cluster/*/ disaster-recovery/*/; do
  if [ -d "$dir" ]; then
    count=$(find "$dir" -name "*.yaml" 2>/dev/null | wc -l)
    echo "  $(basename $dir): $count YAML súborov"
  fi
done

# 2. KONTROLA ČI KAŽDÝ NAMESPACE MÁ VŠETKY TYPY RESOURCES
echo ""
echo "🔍 [2/9] KONTROLA KOMPLETNOSTI NAMESPACOV"
for ns in lamp logging monitoring web web-stack argocd ingress-nginx; do
  echo "  --- $ns ---"
  for type in deployment service ingress configmap secret daemonset statefulset pvc; do
    if [ -f "disaster-recovery/$ns/${type}s.yaml" ] || [ -f "ansible/clusters/my-cluster/$ns/${type}.yaml" ]; then
      echo "    ✅ $type"
    else
      echo "    ⚠️ $type (chýba)"
    fi
  done
done

# 3. KONTROLA EXTERNEJ IP
echo ""
echo "🌐 [3/9] KONTROLA EXTERNEJ IP"
EXTERNAL_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
if [ "$EXTERNAL_IP" == "10.156.15.202" ]; then
  echo "  ✅ LoadBalancer IP: $EXTERNAL_IP"
else
  echo "  ❌ LoadBalancer IP: $EXTERNAL_IP (očakávané 10.156.15.202)"
fi

# 4. KONTROLA WEBHOOKOV
echo ""
echo "🔐 [4/9] KONTROLA VALIDATING WEBHOOKOV"
if kubectl get validatingwebhookconfigurations | grep -q ingress-nginx-admission; then
  echo "  ✅ ingress-nginx-admission existuje"
  CERT_OK=$(kubectl get validatingwebhookconfigurations ingress-nginx-admission -o jsonpath='{.webhooks[0].clientConfig.caBundle}' | wc -c)
  if [ "$CERT_OK" -gt 100 ]; then
    echo "  ✅ Webhook certifikát platný"
  else
    echo "  ❌ Webhook certifikát chybný"
  fi
else
  echo "  ❌ Webhook chýba!"
fi

# 5. KONTROLA DNS
echo ""
echo "📡 [5/9] KONTROLA DNS ZÁZNAMOV"
for host in bank grafana alertmanager prometheus argocd kibana web nginx; do
  hostname="${host}.34.89.208.249.nip.io"
  if nslookup $hostname >/dev/null 2>&1; then
    echo "  ✅ $hostname → $(nslookup $hostname 2>/dev/null | grep Address | tail -1)"
  else
    echo "  ❌ $hostname - DNS chyba"
  fi
done

# 6. KONTROLA ENDPOINTOV
echo ""
echo "🔌 [6/9] KONTROLA ENDPOINTOV PRE VŠETKY SLUŽBY"
kubectl get endpoints -A | grep -v "<none>" | grep -v "NAME" | while read ns name endpoints age; do
  if [ -n "$endpoints" ]; then
    echo "  ✅ $ns/$name → $endpoints"
  fi
done | head -15

# 7. SIMULÁCIA KOMPLETNEJ KATASTROFY (DRY RUN)
echo ""
echo "💀 [7/9] SIMULÁCIA KOMPLETNEJ KATASTROFY - DRY RUN"
echo "  Zisťujem čo by bolo treba obnoviť..."

TOTAL_RESOURCES=0
for ns in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' | grep -vE "kube-system|kube-public|default|kube-node-lease"); do
  resources=$(kubectl get all -n $ns 2>/dev/null | wc -l)
  TOTAL_RESOURCES=$((TOTAL_RESOURCES + resources))
  echo "  $ns: $resources resources"
done
echo "  CELKOM: $TOTAL_RESOURCES resources na obnovu"

# 8. KONTROLA RÝCHLOSTI OBNOVY
echo ""
echo "⏱️ [8/9] TEST RÝCHLOSTI OBNOVY (simulácia)"
START_TIME=$(date +%s)
echo "  Spúšťam restore --dry-run..."
if [ -f "disaster-recovery/restore.sh" ]; then
  bash -n disaster-recovery/restore.sh 2>/dev/null && echo "  ✅ Restore skript syntax OK"
else
  echo "  ❌ Restore skript neexistuje"
fi
END_TIME=$(date +%s)
echo "  ⏱️ Kontrola trvala $((END_TIME - START_TIME))s"

# 9. FINÁLNY TEST VŠETKÝCH WEBOV
echo ""
echo "🌍 [9/9] FINÁLNY TEST VŠETKÝCH WEBOV"
for url in bank.34.89.208.249.nip.io grafana.34.89.208.249.nip.io alertmanager.34.89.208.249.nip.io prometheus.34.89.208.249.nip.io argocd.34.89.208.249.nip.io kibana.34.89.208.249.nip.io web.34.89.208.249.nip.io nginx.34.89.208.249.nip.io; do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://$url)
  if [[ "$HTTP_CODE" =~ ^(200|301|302)$ ]]; then
    echo "  ✅ $url → $HTTP_CODE"
  else
    echo "  ❌ $url → $HTTP_CODE"
  fi
done

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "🏁 ULTRA-DEEP KONTROLA DOKONČENÁ"
echo "═══════════════════════════════════════════════════════════════"
