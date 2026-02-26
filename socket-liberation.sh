#!/bin/bash

echo "🚫 Odstraňujem kolízne Service LB z kube-system..."
kubectl delete daemonset -n kube-system svclb-ingress-nginx-controller --ignore-not-found
kubectl delete daemonset -n kube-system svclb-ingress-nginx-controller-admission --ignore-not-found

echo "🧹 Čistím duplicitné a neplatné Ingressy..."
kubectl delete ing -n lamp bank-ingress --ignore-not-found
kubectl delete ing -n monitoring grafana-ingress prometheus-ingress --ignore-not-found

echo "🔄 Reštartujem Ingress Controller na uvoľnené porty..."
kubectl rollout restart deployment -n ingress-nginx

echo "⏳ Čakám 45s na uvoľnenie socketov a priradenie IP adresy..."
sleep 45

printf "\n--- FINÁLNY STATUS SIETE ---\n"
kubectl get pods -n ingress-nginx
kubectl get ing -A | grep 34.89.208.249
