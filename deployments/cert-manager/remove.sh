#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
PURGE_CRDS="${PURGE_CRDS:-0}"

echo "Removing cert-manager verification namespace..."
kubectl delete namespace cert-manager-test --ignore-not-found=true || true

echo "Removing cert-manager Helm release..."
helm uninstall cert-manager -n cert-manager 2>/dev/null || true

echo "Removing cert-manager namespace..."
kubectl delete namespace cert-manager --ignore-not-found=true || true

if [ "${PURGE_CRDS}" = "1" ]; then
  echo "Removing cert-manager CRDs..."
  kubectl get crd -o name | grep 'cert-manager.io' | xargs -r kubectl delete
else
  echo "Keeping cert-manager CRDs."
  echo "Use -PurgePrerequisites from PowerShell to remove them too."
fi

echo "cert-manager removal completed."
