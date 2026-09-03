#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
FORCE="${FORCE:-0}"

BACKUP_COUNT="$(kubectl -n velero get backups.velero.io --no-headers 2>/dev/null | wc -l | tr -d ' ')"
if [ "${BACKUP_COUNT}" != "0" ] && [ "${FORCE}" != "1" ]; then
  echo "Refusing to remove Velero: ${BACKUP_COUNT} backup object(s) exist." >&2
  echo "Use -Force only if you intentionally want to remove the local backup store." >&2
  exit 1
fi

helm uninstall velero -n velero 2>/dev/null || true
kubectl delete -f /vagrant/deployments/velero/manifests/minio-setup-job.yaml --ignore-not-found=true || true
kubectl delete -f /vagrant/deployments/velero/manifests/minio.yaml --ignore-not-found=true || true
kubectl delete namespace velero --ignore-not-found=true || true
echo "Velero and MinIO removal completed."
