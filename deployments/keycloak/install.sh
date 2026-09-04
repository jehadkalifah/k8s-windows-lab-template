#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

KEYCLOAK_VERSION="${KEYCLOAK_VERSION:-26.7.3}"

echo "===================================================="
echo " Stage 2 - Keycloak Operator + PostgreSQL"
echo "===================================================="
echo "Keycloak/Operator: ${KEYCLOAK_VERSION}"
echo "PostgreSQL:        18"
echo "DB StorageClass:   longhorn"
echo "DB PVC:            5Gi"
echo "Web root:          /keycloak"
echo

kubectl wait --for=condition=Ready nodes --all --timeout=180s

echo "[1/8] Verify dependencies"
if ! kubectl get storageclass longhorn >/dev/null 2>&1; then
  echo "ERROR: Keycloak PostgreSQL requires the Longhorn StorageClass." >&2
  echo "Install Longhorn first:" >&2
  echo "  .\\scripts\\deploy.ps1 longhorn" >&2
  exit 1
fi

if ! kubectl -n istio-ingress get gateway public-gateway >/dev/null 2>&1; then
  echo "ERROR: public-gateway is required for the /keycloak public URL." >&2
  echo "Install Istio first:" >&2
  echo "  .\\scripts\\deploy.ps1 istio" >&2
  exit 1
fi

GATEWAY_IP="$(kubectl -n istio-ingress get gateway public-gateway   -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)"

if [ -z "${GATEWAY_IP}" ]; then
  echo "ERROR: public-gateway has no address." >&2
  exit 1
fi

echo "[2/8] Install official Keycloak Operator"
kubectl create namespace keycloak --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -k "github.com/keycloak/keycloak-k8s-resources/kubernetes?ref=${KEYCLOAK_VERSION}"

kubectl wait --for=condition=Established crd/keycloaks.k8s.keycloak.org --timeout=180s
kubectl -n keycloak rollout status deployment/keycloak-operator --timeout=300s

echo "[3/8] Create database credentials if absent"
if ! kubectl -n keycloak get secret keycloak-db-secret >/dev/null 2>&1; then
  DB_PASSWORD="$(openssl rand -hex 24)"
  kubectl -n keycloak create secret generic keycloak-db-secret     --from-literal=username=keycloak     --from-literal=password="${DB_PASSWORD}"
  unset DB_PASSWORD
else
  echo "Database credentials already exist; preserving them."
fi

echo "[4/8] Deploy PostgreSQL"
kubectl apply -f /vagrant/deployments/keycloak/manifests/postgres.yaml
kubectl -n keycloak rollout status statefulset/keycloak-postgres --timeout=600s

echo "[5/8] Verify PostgreSQL PVC"
kubectl -n keycloak get pvc   -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,STORAGECLASS:.spec.storageClassName,SIZE:.spec.resources.requests.storage'

PVC_CLASS="$(kubectl -n keycloak get pvc data-keycloak-postgres-0   -o jsonpath='{.spec.storageClassName}' 2>/dev/null || true)"
if [ "${PVC_CLASS}" != "longhorn" ]; then
  echo "ERROR: Keycloak PostgreSQL PVC is not using Longhorn." >&2
  exit 1
fi

echo "[6/8] Render and create the Keycloak CR"
sed "s/__GATEWAY_IP__/${GATEWAY_IP}/g"   /vagrant/deployments/keycloak/keycloak.yaml   >/tmp/keycloak.yaml

if grep -q '__GATEWAY_IP__' /tmp/keycloak.yaml; then
  echo "ERROR: Keycloak CR still contains __GATEWAY_IP__." >&2
  exit 1
fi

kubectl apply -f /tmp/keycloak.yaml

echo "[7/8] Wait for Keycloak readiness"
for i in $(seq 1 180); do
  READY="$(kubectl -n keycloak get keycloak keycloak     -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
  [ "${READY}" = "True" ] && break
  sleep 5
done

READY="$(kubectl -n keycloak get keycloak keycloak   -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
if [ "${READY}" != "True" ]; then
  echo "ERROR: Keycloak did not become Ready." >&2
  kubectl -n keycloak get keycloak keycloak -o yaml >&2 || true
  kubectl -n keycloak get pods -o wide >&2 || true
  exit 1
fi

echo "[8/8] Show Keycloak resources"
kubectl -n keycloak get deployment,pod,svc,statefulset,pvc -o wide
echo
kubectl -n keycloak get keycloak keycloak
echo
kubectl -n keycloak get servicemonitor keycloak 2>/dev/null || true

echo
echo "Keycloak deployment completed."
echo "Persistence:"
echo "  PostgreSQL PVC: data-keycloak-postgres-0"
echo "  StorageClass:   longhorn"
echo
echo "Retrieve the temporary admin credentials:"
echo "  .\\scripts\\keycloak-admin.ps1"
echo
echo "Publish/reconcile:"
echo "  .\\scripts\\publish.ps1 keycloak"
