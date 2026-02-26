#!/bin/bash
# 1. Zmazanie mŕtvych ingress-ov, ktoré blokujú prevádzku
kubectl delete ing bank-ingress-final -n lamp --ignore-not-found
kubectl delete ing grafana-ingress -n lamp --ignore-not-found
kubectl delete ing lamp-ingress -n lamp --ignore-not-found

# 2. Nastavenie správnej Ingress triedy pre Argo CD (Fix Login Loop)
kubectl patch ingress argocd-server-ingress -n argocd --type merge -p '{"spec":{"ingressClassName":"nginx"}}'

# 3. Anotácie pre Nginx (Buffery pre Argo CD a Monitoring)
kubectl annotate ingress argocd-server-ingress -n argocd \
  nginx.ingress.kubernetes.io/proxy-body-size="64m" \
  nginx.ingress.kubernetes.io/proxy-buffer-size="128k" \
  nginx.ingress.kubernetes.io/proxy-buffers-number="4" --overwrite

# 4. Kontrola funkčnosti backendo-ov v monitoringu
kubectl patch ingress grafana-ingress -n monitoring --type merge -p '{"spec":{"ingressClassName":"nginx"}}'
