#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "=== Helm release ==="
helm list -n vault || true

echo
echo "=== StatefulSet / Deployments ==="
kubectl -n vault get statefulset,deployment -o wide || true

echo
echo "=== Vault pods ==="
kubectl -n vault get pods -o wide || true

echo
echo "=== Vault PVCs ==="
kubectl -n vault get pvc \
  -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,STORAGECLASS:.spec.storageClassName,SIZE:.spec.resources.requests.storage,VOLUME:.spec.volumeName' \
  2>/dev/null || true

echo
echo "=== Vault services ==="
kubectl -n vault get svc -o wide || true

echo
echo "=== Vault UI Service endpoints ==="
kubectl -n vault get endpointslice \
  -l kubernetes.io/service-name=vault-ui \
  -o wide 2>/dev/null || true

echo
echo "UI service behavior:"
echo "  publishNotReadyAddresses: true"
echo "  activeVaultPodOnly:      false"

echo
echo "=== Vault server state ==="
for pod in vault-0 vault-1 vault-2; do
  if kubectl -n vault get pod "${pod}" >/dev/null 2>&1; then
    echo
    echo "--- ${pod} ---"
    kubectl -n vault exec "${pod}" -- \
      env VAULT_ADDR=http://127.0.0.1:8200 vault status 2>/dev/null || true
  fi
done

echo
echo "Expected StorageClass: longhorn"
echo "Expected PVC count:    3"
echo
echo "If initialized but Sealed=true after a restart:"
echo "  .\\scripts\\vault-unseal.ps1"
