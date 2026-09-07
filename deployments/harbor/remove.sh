#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

FORCE="${FORCE:-0}"

kubectl -n harbor delete httproute harbor-ui --ignore-not-found=true || true
helm uninstall harbor -n harbor 2>/dev/null || true

if [ "${FORCE}" = "1" ]; then
  echo "FORCE=1: deleting Harbor namespace, PVCs and generated credentials."
  kubectl delete namespace harbor --ignore-not-found=true --wait=true
else
  echo
  echo "Harbor release removed."
  echo "Persistent PVCs and generated Harbor credentials are preserved."
  echo "Delete everything with:"
  echo "  .\\scripts\\remove-deployment.ps1 harbor -Force"
fi
