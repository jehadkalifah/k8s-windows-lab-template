#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "=== Helm release ==="
helm list -n velero
echo
echo "=== Velero / MinIO pods ==="
kubectl -n velero get pods -o wide
echo
echo "=== BackupStorageLocation ==="
kubectl -n velero get backupstoragelocation
echo
echo "=== Backups ==="
velero backup get 2>/dev/null || kubectl -n velero get backups.velero.io
echo
echo "=== MinIO PVC ==="
kubectl -n velero get pvc minio-data
