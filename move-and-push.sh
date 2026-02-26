echo "=== PRESUNAM VECTOR.YAML DO ROOT REPO ==="
mv ansible/clusters/my-cluster/logging/vector.yaml /home/ondrejko_gulkas/mon/vector.yaml
echo "Presunute: $(ls /home/ondrejko_gulkas/mon/vector.yaml)"

echo "" && echo "=== GIT STATUS ==="
cd /home/ondrejko_gulkas/mon && git status

echo "" && echo "=== GIT ADD + COMMIT + PUSH ==="
git add vector.yaml
git add -u ansible/clusters/my-cluster/logging/vector.yaml
git commit -m "feat: move vector.yaml to repo root"
git push origin HEAD

echo "" && echo "=== OVERENIE NA GITE ==="
git log --oneline -3
