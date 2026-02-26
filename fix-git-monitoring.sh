echo "=== HLADAM GRAFANA INGRESS MANIFEST V REPO ==="
find /home/ondrejko_gulkas/mon -name "*.yaml" | xargs grep -l "grafana-ingress" 2>/dev/null

echo "" && echo "=== HLADAM ALERTMANAGER MANIFEST ==="
find /home/ondrejko_gulkas/mon -name "*.yaml" | xargs grep -l "alertmanager" 2>/dev/null

echo "" && echo "=== OBSAH MONITORING ADRESARA ==="
find /home/ondrejko_gulkas/mon -path "*/monitoring*" -name "*.yaml" | head -20
ls /home/ondrejko_gulkas/mon/ansible/clusters/my-cluster/monitoring/ 2>/dev/null || \
find /home/ondrejko_gulkas/mon -name "*.yaml" | xargs grep -l "grafana" 2>/dev/null
