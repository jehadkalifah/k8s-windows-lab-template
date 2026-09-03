#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "=== Helm release ==="
helm list -n cert-manager

echo
echo "=== cert-manager workloads ==="
kubectl -n cert-manager get deployment,pod

echo
echo "=== cert-manager CRDs ==="
kubectl get crd \
  certificates.cert-manager.io \
  certificaterequests.cert-manager.io \
  issuers.cert-manager.io \
  clusterissuers.cert-manager.io

echo
echo "=== Verification objects ==="
kubectl -n cert-manager-test get issuer,certificate,secret 2>/dev/null || true

echo
READY="$(kubectl -n cert-manager-test get certificate lab-test-cert \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"

if [ "${READY}" = "True" ]; then
  echo "Certificate verification: Ready"
else
  echo "Certificate verification: Not Ready / not installed"
fi
