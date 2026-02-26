#!/bin/bash
echo "🔧 INGRESS WEBHOOK FIX"
kubectl delete validatingwebhookconfigurations ingress-nginx-admission 2>/dev/null
kubectl patch svc -n ingress-nginx ingress-nginx-controller -p '{"spec":{"type":"LoadBalancer"}}'
