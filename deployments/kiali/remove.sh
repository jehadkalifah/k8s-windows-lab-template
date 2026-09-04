#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

kubectl -n istio-system delete kiali kiali --ignore-not-found=true --wait=true || true
for i in $(seq 1 60); do
  ! kubectl -n istio-system get deployment kiali >/dev/null 2>&1 && break
  sleep 2
done
helm uninstall kiali-operator -n kiali-operator 2>/dev/null || true
kubectl delete namespace kiali-operator --ignore-not-found=true || true

echo "Kiali Operator and Kiali Server removal completed."
echo "Istio, Prometheus and Grafana were kept."
