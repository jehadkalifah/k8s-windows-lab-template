#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

GATEWAY_NAMESPACE="${GATEWAY_NAMESPACE:-istio-ingress}"
GATEWAY_NAME="${GATEWAY_NAME:-public-gateway}"

echo "=== Shared Gateway ==="
kubectl -n "${GATEWAY_NAMESPACE}" get gateway "${GATEWAY_NAME}" -o wide

IP="$(kubectl -n "${GATEWAY_NAMESPACE}" get gateway "${GATEWAY_NAME}" -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)"

echo
echo "=== HTTPRoutes ==="
kubectl get httproute -A

echo
echo "=== Published URLs ==="
if [ -z "${IP}" ]; then
  echo "Gateway IP is not available."
  exit 0
fi

print_url() {
  local ns="$1"
  local route="$2"
  local path="$3"
  if kubectl -n "${ns}" get httproute "${route}" >/dev/null 2>&1; then
    printf "%-15s http://%s%s\n" "${route}" "${IP}" "${path}"
  fi
}

print_url demo demo /demo
if kubectl -n longhorn-system get httproute longhorn-ui >/dev/null 2>&1; then
  LONGHORN_HOST="$(kubectl -n longhorn-system get httproute longhorn-ui -o jsonpath='{.spec.hostnames[0]}' 2>/dev/null || true)"
  printf "%-15s http://%s%s\n" "longhorn-entry" "${IP}" "/longhorn"
  if [ -n "${LONGHORN_HOST}" ]; then
    printf "%-15s http://%s/\n" "longhorn" "${LONGHORN_HOST}"
  else
    printf "%-15s %s\n" "longhorn" "ERROR: live HTTPRoute hostname is empty"
    echo "  Run: .\\scripts\\publish.ps1 longhorn"
  fi
fi


if kubectl -n vault get httproute vault-ui >/dev/null 2>&1; then
  VAULT_HOST="$(kubectl -n vault get httproute vault-ui -o jsonpath='{.spec.hostnames[0]}' 2>/dev/null || true)"
  printf "%-15s http://%s%s\n" "vault-entry" "${IP}" "/vault"
  if [ -n "${VAULT_HOST}" ]; then
    printf "%-15s http://%s/\n" "vault" "${VAULT_HOST}"
  else
    printf "%-15s %s\n" "vault" "ERROR: live HTTPRoute hostname is empty"
    echo "  Run: .\\scripts\\publish.ps1 vault"
  fi
fi

print_url monitoring monitoring-ui /grafana
if kubectl -n monitoring get httproute monitoring-ui >/dev/null 2>&1; then
  printf "%-15s http://%s%s\n" "prometheus" "${IP}" "/prometheus"
  printf "%-15s http://%s%s\n" "alertmanager" "${IP}" "/alertmanager"
fi
print_url argocd argocd-ui /argocd
print_url istio-system kiali-ui /kiali
print_url keycloak keycloak-ui /keycloak
print_url jenkins jenkins-http-route /jenkins
print_url velero minio-console /minio/

echo
echo "Components without a browser path:"
echo "  cert-manager  -> Kubernetes CRDs/controllers only"
echo "  Velero CLI/API -> use kubectl/velero; MinIO console is published separately"


echo
echo "=== Jenkins external VM backend ==="
if kubectl -n jenkins get endpointslice jenkins-external >/dev/null 2>&1; then
  kubectl -n jenkins get service jenkins-external-svc -o wide
  kubectl -n jenkins get endpointslice jenkins-external -o wide
fi
