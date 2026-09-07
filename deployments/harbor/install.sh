#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

HARBOR_CHART_VERSION="${HARBOR_CHART_VERSION:-1.19.1}"
HARBOR_APP_VERSION="${HARBOR_APP_VERSION:-2.15.1}"
GATEWAY_NAMESPACE="${GATEWAY_NAMESPACE:-istio-ingress}"
GATEWAY_NAME="${GATEWAY_NAME:-public-gateway}"
HARBOR_PUBLISH_HOST="${HARBOR_PUBLISH_HOST:-}"

echo "===================================================="
echo " Stage 2 - Harbor Private Registry"
echo "===================================================="
echo "Harbor chart: ${HARBOR_CHART_VERSION}"
echo "Harbor app:   ${HARBOR_APP_VERSION}"
echo "StorageClass: local-path (K3s node-local; lab only)"
echo "Exposure:     shared Istio Gateway hostname"
echo

kubectl wait --for=condition=Ready nodes --all --timeout=180s

if ! kubectl -n "${GATEWAY_NAMESPACE}" get gateway "${GATEWAY_NAME}" >/dev/null 2>&1; then
  echo "ERROR: Harbor is deployed after Istio in this lab." >&2
  echo "Install Istio first:" >&2
  echo "  .\\scripts\\deploy.ps1 istio" >&2
  exit 1
fi

PROGRAMMED="$(kubectl -n "${GATEWAY_NAMESPACE}" get gateway "${GATEWAY_NAME}" \
  -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || true)"

if [ "${PROGRAMMED}" != "True" ]; then
  echo "ERROR: ${GATEWAY_NAMESPACE}/${GATEWAY_NAME} is not Programmed." >&2
  exit 1
fi

GATEWAY_IP="$(kubectl -n "${GATEWAY_NAMESPACE}" get gateway "${GATEWAY_NAME}" \
  -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)"

if [ -z "${GATEWAY_IP}" ]; then
  echo "ERROR: Gateway has no published IP address." >&2
  exit 1
fi

if [ -z "${HARBOR_PUBLISH_HOST}" ]; then
  IP_DASH="${GATEWAY_IP//./-}"
  HARBOR_PUBLISH_HOST="harbor.${IP_DASH}.nip.io"
fi

HARBOR_EXTERNAL_URL="http://${HARBOR_PUBLISH_HOST}"

echo "Gateway IP:   ${GATEWAY_IP}"
echo "Harbor host:  ${HARBOR_PUBLISH_HOST}"
echo "External URL: ${HARBOR_EXTERNAL_URL}"
echo

echo "[1/8] Create Harbor namespace"
kubectl create namespace harbor --dry-run=client -o yaml | kubectl apply -f -

echo "[2/8] Ensure K3s local-path StorageClass"
bash /vagrant/deployments/k3s-local-storage/ensure.sh

LOCAL_PROVISIONER="$(kubectl get storageclass local-path \
  -o jsonpath='{.provisioner}' 2>/dev/null || true)"

if [ "${LOCAL_PROVISIONER}" != "rancher.io/local-path" ]; then
  echo "ERROR: local-path validation failed after K3s local-storage repair." >&2
  exit 1
fi

# Existing Harbor PVCs cannot change StorageClass in place.
EXISTING_PVCS="$(kubectl -n harbor get pvc -o name 2>/dev/null || true)"
if [ -n "${EXISTING_PVCS}" ]; then
  NON_LOCAL_PVCS="$(kubectl -n harbor get pvc \
    -o jsonpath='{range .items[?(@.spec.storageClassName!="local-path")]}{.metadata.name}{"="}{.spec.storageClassName}{"\n"}{end}' \
    2>/dev/null || true)"

  if [ -n "${NON_LOCAL_PVCS}" ]; then
    echo "ERROR: Existing Harbor PVCs use an incompatible StorageClass:" >&2
    echo "${NON_LOCAL_PVCS}" >&2
    echo >&2
    echo "Harbor now uses K3s local-path storage for this lab." >&2
    echo "Kubernetes cannot change storageClass on an existing PVC." >&2
    echo >&2
    echo "If this is a fresh Harbor installation with no data to preserve, run:" >&2
    echo "  .\\scripts\\remove-deployment.ps1 harbor -Force" >&2
    echo "  .\\scripts\\deploy.ps1 harbor" >&2
    exit 1
  fi
fi

echo "[3/8] Preserve/create Harbor admin credential"
if ! kubectl -n harbor get secret harbor-admin-password >/dev/null 2>&1; then
  ADMIN_PASSWORD="$(openssl rand -hex 16)"
  kubectl -n harbor create secret generic harbor-admin-password \
    --from-literal=HARBOR_ADMIN_PASSWORD="${ADMIN_PASSWORD}" >/dev/null
  unset ADMIN_PASSWORD
  echo "Created harbor-admin-password."
else
  echo "Keeping existing harbor-admin-password."
fi

echo "[4/8] Preserve/create Harbor encryption secret"
if ! kubectl -n harbor get secret harbor-core-secret-key >/dev/null 2>&1; then
  CORE_SECRET_KEY="$(openssl rand -hex 8)"
  kubectl -n harbor create secret generic harbor-core-secret-key \
    --from-literal=secretKey="${CORE_SECRET_KEY}" >/dev/null
  unset CORE_SECRET_KEY
  echo "Created harbor-core-secret-key."
else
  echo "Keeping existing harbor-core-secret-key."
fi

echo "[5/8] Render Harbor values"
sed "s|__HARBOR_EXTERNAL_URL__|${HARBOR_EXTERNAL_URL}|g" \
  /vagrant/deployments/harbor/values.yaml.tpl \
  >/tmp/harbor-values.yaml

if grep -q '__HARBOR_EXTERNAL_URL__' /tmp/harbor-values.yaml; then
  echo "ERROR: unresolved Harbor external URL placeholder remains." >&2
  exit 1
fi

echo "[6/8] Add/update official Harbor Helm repository"
helm repo add harbor https://helm.goharbor.io --force-update
helm repo update

echo "[7/8] Install/upgrade Harbor"
helm template harbor harbor/harbor \
  --namespace harbor \
  --version "${HARBOR_CHART_VERSION}" \
  -f /tmp/harbor-values.yaml \
  >/tmp/harbor-rendered.yaml

test -s /tmp/harbor-rendered.yaml

# Verify the values file contains all five Harbor local-path selections.
# This validates our input independently from Helm's YAML quoting style.
VALUES_LOCAL_PATH_COUNT="$(
  grep -Ec '^[[:space:]]*storageClass:[[:space:]]*"?local-path"?[[:space:]]*$' \
    /tmp/harbor-values.yaml || true
)"

if [ "${VALUES_LOCAL_PATH_COUNT}" -ne 5 ]; then
  echo "ERROR: Harbor values should contain exactly five local-path StorageClass selections." >&2
  echo "Values local-path count: ${VALUES_LOCAL_PATH_COUNT}" >&2
  echo "Matching values:" >&2
  grep -En 'storageClass:' /tmp/harbor-values.yaml >&2 || true
  exit 1
fi

# Helm renders different Harbor PVC templates with slightly different YAML
# formatting. In particular, StatefulSet volumeClaimTemplates can render:
#
#   storageClassName: "local-path"
#
# while standalone PVCs can render:
#
#   storageClassName: local-path
#
# Therefore the rendered validation MUST accept both quoted and unquoted forms.
if grep -E '^[[:space:]]*storageClassName:[[:space:]]*"?longhorn(-harbor)?"?[[:space:]]*$' \
    /tmp/harbor-rendered.yaml >/dev/null 2>&1; then
  echo "ERROR: rendered Harbor chart still contains a Longhorn StorageClass." >&2
  echo "Rendered StorageClass lines:" >&2
  grep -En 'storageClassName:' /tmp/harbor-rendered.yaml >&2 || true
  exit 1
fi

RENDERED_LOCAL_PATH_COUNT="$(
  grep -Ec '^[[:space:]]*storageClassName:[[:space:]]*"?local-path"?[[:space:]]*$' \
    /tmp/harbor-rendered.yaml || true
)"

if [ "${RENDERED_LOCAL_PATH_COUNT}" -lt 5 ]; then
  echo "ERROR: expected at least five rendered Harbor PVC/PVC-template references to local-path." >&2
  echo "Rendered local-path count: ${RENDERED_LOCAL_PATH_COUNT}" >&2
  echo "All rendered StorageClass lines:" >&2
  grep -En 'storageClassName:' /tmp/harbor-rendered.yaml >&2 || true
  exit 1
fi

echo "Harbor storage validation passed:"
echo "  values local-path selections:   ${VALUES_LOCAL_PATH_COUNT}"
echo "  rendered local-path references: ${RENDERED_LOCAL_PATH_COUNT}"

helm upgrade --install harbor harbor/harbor \
  --namespace harbor \
  --version "${HARBOR_CHART_VERSION}" \
  -f /tmp/harbor-values.yaml \
  --wait \
  --timeout 15m

echo "[8/8] Verify Harbor workloads and storage"
kubectl -n harbor get deployments,statefulsets,pods,svc,pvc -o wide

BAD_SC="$(kubectl -n harbor get pvc \
  -o jsonpath='{range .items[?(@.spec.storageClassName!="local-path")]}{.metadata.name}{"="}{.spec.storageClassName}{"\n"}{end}' \
  2>/dev/null || true)"

if [ -n "${BAD_SC}" ]; then
  echo "ERROR: Harbor has PVCs that are not using local-path:" >&2
  echo "${BAD_SC}" >&2
  exit 1
fi

HARBOR_PVC_COUNT="$(kubectl -n harbor get pvc --no-headers 2>/dev/null | wc -l | tr -d ' ')"

if [ "${HARBOR_PVC_COUNT}" -lt 5 ]; then
  echo "ERROR: expected at least five Harbor PVCs after installation." >&2
  echo "Actual PVC count: ${HARBOR_PVC_COUNT}" >&2
  kubectl -n harbor get pvc -o wide >&2 || true
  exit 1
fi

echo "Harbor PVC validation passed:"
echo "  PVC count: ${HARBOR_PVC_COUNT}"
echo "  StorageClass: local-path"

echo
echo "Harbor installation completed."
echo "Harbor storage uses K3s local-path; no Harbor Longhorn replicas are created."
echo "Publishing is reconciled automatically by scripts/deploy.ps1."
echo
echo "Harbor UI:"
echo "  ${HARBOR_EXTERNAL_URL}"
echo
echo "Admin user: admin"
echo "Retrieve the generated admin password from Windows with:"
echo "  .\\scripts\\harbor-admin.ps1"
