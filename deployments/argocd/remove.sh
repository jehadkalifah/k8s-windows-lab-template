#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
helm uninstall argocd -n argocd 2>/dev/null || true
kubectl delete namespace argocd --ignore-not-found=true || true
echo "Argo CD removal completed."
