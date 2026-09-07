#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

helm uninstall reloader -n reloader 2>/dev/null || true
kubectl delete namespace reloader --ignore-not-found=true || true

echo "Stakater Reloader removal completed."
echo "Application annotations are left unchanged; they are harmless while Reloader is absent."
