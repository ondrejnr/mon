#!/bin/bash
set -e
echo "🚨 DISASTER RECOVERY - OBNOVA Z KONEČNÉHO FUNKČNÉHO STAVU"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Aplikácia namespace
kubectl apply -f $SCRIPT_DIR/argocd/ 2>/dev/null || true
kubectl apply -f $SCRIPT_DIR/ingress-nginx/ 2>/dev/null || true
kubectl apply -f $SCRIPT_DIR/lamp/ 2>/dev/null || true
kubectl apply -f $SCRIPT_DIR/logging/ 2>/dev/null || true
kubectl apply -f $SCRIPT_DIR/monitoring/ 2>/dev/null || true
kubectl apply -f $SCRIPT_DIR/web/ 2>/dev/null || true
kubectl apply -f $SCRIPT_DIR/web-stack/ 2>/dev/null || true

# Aplikácia clusterových rolí
kubectl apply -f $SCRIPT_DIR/logging/vector-clusterrole.yaml 2>/dev/null || true
kubectl apply -f $SCRIPT_DIR/logging/vector-clusterrolebinding.yaml 2>/dev/null || true

echo "✅ Obnova dokončená. Čakám 30 sekúnd na stabilizáciu..."
sleep 30
kubectl get pods -A
