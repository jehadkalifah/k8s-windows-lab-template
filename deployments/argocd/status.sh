#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "=== Helm release ==="
helm list -n argocd
echo
echo "=== Pods ==="
kubectl -n argocd get pods -o wide
echo
echo "=== Services ==="
kubectl -n argocd get svc
echo
echo "=== Argo CD CRDs ==="
kubectl get crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io 2>/dev/null || true
