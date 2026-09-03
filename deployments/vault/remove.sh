#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

FORCE="${FORCE:-0}"

PVC_COUNT="$(kubectl -n vault get pvc --no-headers 2>/dev/null | wc -l | tr -d ' ')"

if [ "${PVC_COUNT}" != "0" ] && [ "${FORCE}" != "1" ]; then
  echo "Refusing to remove Vault: ${PVC_COUNT} persistent PVC(s) exist." >&2
  echo "Vault data is stored on these Longhorn volumes." >&2
  echo "Use -Force only if you intentionally want to delete Vault and its data." >&2
  exit 1
fi

helm uninstall vault -n vault 2>/dev/null || true
kubectl delete namespace vault --ignore-not-found=true || true

echo "Vault removal requested."
