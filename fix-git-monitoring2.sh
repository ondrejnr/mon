echo "=== STRUKTURA REPO ==="
find /home/ondrejko_gulkas/mon -name "*.yaml" | sort

echo "" && echo "=== KUSTOMIZATION MONITORING ==="
cat /home/ondrejko_gulkas/mon/ansible/clusters/my-cluster/monitoring/kustomization.yaml 2>/dev/null || \
find /home/ondrejko_gulkas/mon -path "*monitoring*kustomization*" | xargs cat 2>/dev/null

echo "" && echo "=== VSETKY MONITORING YAML ==="
find /home/ondrejko_gulkas/mon -path "*monitoring*" -name "*.yaml" | while read f; do
  echo "--- $f ---"
  cat "$f"
  echo ""
done
