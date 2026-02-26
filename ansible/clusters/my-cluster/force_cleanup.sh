#!/bin/bash
echo "=== Odstraňovanie Finalizers zo zaseknutých Flux objektov ==="
kubectl patch kustomization flux-system -n flux-system --type json -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null || true
kubectl patch gitrepository flux-system -n flux-system --type json -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null || true

echo "=== Čistenie Terminating namespaceov ==="
for ns in $(kubectl get ns | grep Terminating | awk '{print $1}'); do
  echo "Uvoľňujem namespace: $ns"
  kubectl get ns "$ns" -o json | sed 's/"kubernetes"//' | kubectl replace --raw /api/v1/namespaces/"$ns"/finalize -f -
done
