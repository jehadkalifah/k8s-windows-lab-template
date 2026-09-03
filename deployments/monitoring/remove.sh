#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
helm uninstall monitoring -n monitoring 2>/dev/null || true
kubectl delete namespace monitoring --ignore-not-found=true || true
echo "Monitoring removal completed."
