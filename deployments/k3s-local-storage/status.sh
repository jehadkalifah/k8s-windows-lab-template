#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "=== K3s config disable block ==="
awk '
  /^disable:/ {print; in_disable=1; next}
  in_disable && /^[[:space:]]*-/ {print; next}
  in_disable {exit}
' /etc/rancher/k3s/config.yaml || true

echo
echo "=== local-path StorageClass ==="
kubectl get storageclass local-path -o wide 2>/dev/null || true

echo
echo "=== Local Path Provisioner ==="
kubectl -n kube-system get deployment local-path-provisioner -o wide 2>/dev/null || true
kubectl -n kube-system get pods -o wide 2>/dev/null | grep -i local-path || true
