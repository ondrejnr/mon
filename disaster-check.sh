#!/bin/bash
echo "═══════════════════════════════════════════════════════════════"
echo "🔍 KONTROLA HAVARIJNEJ PRIPRAVENOSTI - $(date)"
echo "═══════════════════════════════════════════════════════════════"

cd /home/ondrejko_gulkas/mon

echo ""
echo "📁 [1/6] EXISTUJE DISASTER RECOVERY ADRESÁR?"
ls -la disaster-recovery/ 2>/dev/null || echo "❌ CHÝBA!"

echo ""
echo "📝 [2/6] EXISTUJÚ ZÁLOHY INGRESSOV?"
find disaster-recovery -name "*ingress*.yaml" 2>/dev/null | wc -l || echo "❌ CHÝBA!"

echo ""
echo "🔄 [3/6] EXISTUJE WEBHOOK FIX SKRIPT?"
ls -la disaster-recovery/ingress-webhook-fix.sh 2>/dev/null && echo "✅ ÁNO" || echo "❌ CHÝBA!"

echo ""
echo "⚙️ [4/6] JE V GITE KONFIGURÁCIA INGRESS LOADBALANCERA?"
ls -la ansible/clusters/my-cluster/ingress-nginx/service.yaml 2>/dev/null && echo "✅ ÁNO" || echo "⚠️ CHÝBA (treba pridať)"

echo ""
echo "📊 [5/6] SÚ V GITE VŠETKY NAMESPACE?"
for ns in lamp logging monitoring web web-stack argocd ingress-nginx; do
  if [ -d "ansible/clusters/my-cluster/$ns" ] || [ -d "disaster-recovery/$ns" ]; then
    echo "  ✅ $ns"
  else
    echo "  ⚠️ $ns (iba v disaster-recovery?)"
  fi
done

echo ""
echo "🚀 [6/6] TEST - ZMAZANIE A OBNOVA WEBHOOKU"
echo "Simulujem výpadok webhooku..."
kubectl delete validatingwebhookconfigurations ingress-nginx-admission --wait=false 2>/dev/null
echo "Spúšťam fix skript..."
./disaster-recovery/ingress-webhook-fix.sh
echo "Kontrolujem či Ingressy žijú..."
kubectl get ingress -A | grep -c "" || echo "⚠️ Problém"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ HOTOVO - Chýbajúce veci treba doplniť"
