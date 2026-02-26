echo "=== GRAFANA INGRESS RIADKY V SUBORE ==="
grep -n "grafana\|number:" \
  /home/ondrejko_gulkas/mon/ansible/clusters/my-cluster/monitoring/setup.yaml

echo "" && echo "=== PYTHON OPRAVA - PODLA RIADKU ==="
python3 << 'PYEOF'
path = '/home/ondrejko_gulkas/mon/ansible/clusters/my-cluster/monitoring/setup.yaml'
with open(path, 'r') as f:
    lines = f.readlines()

in_grafana_ingress = False
changed = False
for i, line in enumerate(lines):
    if 'grafana-ingress' in line:
        in_grafana_ingress = True
    if 'prometheus-ingress' in line or 'alertmanager-ingress' in line:
        in_grafana_ingress = False
    if in_grafana_ingress and 'number: 80' in line:
        print(f"PRED [{i+1}]: {line.rstrip()}")
        lines[i] = line.replace('number: 80', 'number: 3000')
        print(f"PO   [{i+1}]: {lines[i].rstrip()}")
        changed = True

if changed:
    with open(path, 'w') as f:
        f.writelines(lines)
    print("Subor ulozeny")
else:
    print("NENASIEL som 'number: 80' v grafana-ingress sekcii!")
    print("Vypis grafana sekcie:")
    in_g = False
    for i, l in enumerate(lines):
        if 'grafana-ingress' in l: in_g = True
        if in_g: print(f"  [{i+1}] {l.rstrip()}")
        if in_g and i > 0 and 'pathType' in l: break
PYEOF

echo "" && echo "=== GIT PUSH ==="
cd /home/ondrejko_gulkas/mon
git add ansible/clusters/my-cluster/monitoring/setup.yaml
git diff --cached | grep "^[+-].*number"
git commit -m "fix: grafana ingress port 3000" && git push origin main || echo "nic na commit"

echo "" && echo "=== ARGOCD REFRESH ==="
kubectl annotate application monitoring-stack -n argocd argocd.argoproj.io/refresh=hard --overwrite
sleep 20 && curl -s -o /dev/null -w "GRAFANA: %{http_code}\n" http://grafana.34.89.208.249.nip.io
