#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "=== Helm release ==="
helm list -n longhorn-system
echo
echo "=== Pods ==="
kubectl -n longhorn-system get pods -o wide
echo
echo "=== StorageClass ==="
kubectl get storageclass
echo
echo "=== Longhorn nodes ==="
kubectl -n longhorn-system get nodes.longhorn.io 2>/dev/null || true
echo
echo "=== Longhorn volumes ==="
kubectl -n longhorn-system get volumes.longhorn.io 2>/dev/null || true
