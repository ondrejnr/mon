echo "=== AKTUALNY PORT V GIT ==="
grep -n "number:" /home/ondrejko_gulkas/mon/ansible/clusters/my-cluster/monitoring/setup.yaml

echo "" && echo "=== HLADAM GRAFANA INGRESS SEKCIU ==="
grep -n "grafana-ingress\|number: 80\|number: 3000" \
  /home/ondrejko_gulkas/mon/ansible/clusters/my-cluster/monitoring/setup.yaml

echo "" && echo "=== PYTHON REPLACE - PRESNA OPRAVA ==="
python3 << 'PYEOF'
with open('/home/ondrejko_gulkas/mon/ansible/clusters/my-cluster/monitoring/setup.yaml', 'r') as f:
    content = f.read()

# Najdi grafana-ingress sekciu a zmen port 80 na 3000
lines = content.split('\n')
in_grafana_ingress = False
result = []
for i, line in enumerate(lines):
    if 'name: grafana-ingress' in line:
        in_grafana_ingress = True
    if in_grafana_ingress and 'number: 80' in line:
        line = line.replace('number: 80', 'number: 3000')
        in_grafana_ingress = False
        print(f"Opraveny riadok {i+1}: {line.strip()}")
    result.append(line)

with open('/home/ondrejko_gulkas/mon/ansible/clusters/my-cluster/monitoring/setup.yaml', 'w') as f:
    f.write('\n'.join(result))
print("Hotovo")
PYEOF

echo "" && echo "=== OVERENIE ==="
grep -A15 "grafana-ingress" \
  /home/ondrejko_gulkas/mon/ansible/clusters/my-cluster/monitoring/setup.yaml | grep number

echo "" && echo "=== GIT PUSH ==="
cd /home/ondrejko_gulkas/mon
git add ansible/clusters/my-cluster/monitoring/setup.yaml
git commit -m "fix: grafana ingress port 80 → 3000"
git push origin main

echo "" && echo "=== ARGOCD SYNC ==="
kubectl annotate application monitoring-stack -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite
sleep 20

echo "" && echo "=== HTTP TESTY ==="
for url in bank.34.89.208.249.nip.io grafana.34.89.208.249.nip.io \
  alertmanager.34.89.208.249.nip.io prometheus.34.89.208.249.nip.io argocd.34.89.208.249.nip.io; do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://$url)
  echo "  $code → http://$url"
done
