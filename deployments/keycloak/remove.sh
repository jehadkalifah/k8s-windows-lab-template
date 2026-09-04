#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

FORCE="${FORCE:-0}"

PVC_COUNT="$(kubectl -n keycloak get pvc --no-headers 2>/dev/null | wc -l | tr -d ' ')"

if [ "${PVC_COUNT}" != "0" ] && [ "${FORCE}" != "1" ]; then
  echo "Refusing to remove Keycloak: ${PVC_COUNT} persistent PVC(s) exist." >&2
  echo "The PostgreSQL database contains Keycloak realms/users/clients." >&2
  echo "Use -Force only if deleting this Keycloak data is intentional." >&2
  exit 1
fi

kubectl -n keycloak delete keycloak keycloak --ignore-not-found=true --wait=true || true
kubectl -n keycloak delete statefulset keycloak-postgres --ignore-not-found=true || true
kubectl -n keycloak delete service keycloak-postgres --ignore-not-found=true || true

if [ "${FORCE}" = "1" ]; then
  kubectl -n keycloak delete pvc --all --ignore-not-found=true || true
  kubectl -n keycloak delete secret keycloak-db-secret --ignore-not-found=true || true
fi

# Remove the operator last.
kubectl delete -k "github.com/keycloak/keycloak-k8s-resources/kubernetes?ref=26.7.3" \
  --ignore-not-found=true || true

kubectl delete namespace keycloak --ignore-not-found=true || true

echo "Keycloak Operator, Keycloak and PostgreSQL removal requested."
