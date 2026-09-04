#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "=== Kiali Operator Helm release ==="
helm list -n kiali-operator || true

echo
echo "=== Kiali Operator ==="
kubectl -n kiali-operator get deployment,pods -o wide || true

echo
echo "=== Kiali CR ==="
kubectl -n istio-system get kiali kiali -o wide 2>/dev/null || true

echo
echo "=== Kiali Server ==="
kubectl -n istio-system get deployment kiali -o wide 2>/dev/null || true
kubectl -n istio-system get pods -l app.kubernetes.io/name=kiali -o wide 2>/dev/null || true
kubectl -n istio-system get svc kiali -o wide 2>/dev/null || true

echo
echo "=== Kiali endpoints ==="
kubectl -n istio-system get endpointslice -l kubernetes.io/service-name=kiali -o wide 2>/dev/null || true

echo
echo "=== Dependencies ==="
kubectl -n istio-system get deployment istiod -o wide 2>/dev/null || true
kubectl -n monitoring get svc monitoring-kube-prometheus-prometheus -o wide 2>/dev/null || true

echo
echo "Persistence:"
echo "  Kiali PVC: none required (stateless)"
echo "  Metrics:   Prometheus in namespace monitoring"
