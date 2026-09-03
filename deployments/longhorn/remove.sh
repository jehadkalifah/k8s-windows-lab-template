#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
FORCE="${FORCE:-0}"

PV_COUNT="$(kubectl get pv -o json 2>/dev/null | jq '[.items[] | select(.spec.storageClassName=="longhorn")] | length')"
if [ "${PV_COUNT}" != "0" ] && [ "${FORCE}" != "1" ]; then
  echo "Refusing to remove Longhorn: ${PV_COUNT} PV(s) still use storageClass=longhorn." >&2
  echo "Remove/migrate them first or use -Force." >&2
  exit 1
fi

helm uninstall longhorn -n longhorn-system 2>/dev/null || true
kubectl delete namespace longhorn-system --ignore-not-found=true || true
echo "Longhorn removal requested."
