#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

VAULT_CHART_VERSION="${VAULT_CHART_VERSION:-0.34.1}"
VAULT_APP_VERSION="${VAULT_APP_VERSION:-2.0.4}"

echo "===================================================="
echo " Stage 2 - HashiCorp Vault"
echo "===================================================="
echo "Vault Helm chart: ${VAULT_CHART_VERSION}"
echo "Vault app:        ${VAULT_APP_VERSION}"
echo "Mode:             HA + Integrated Storage (Raft)"
echo "StorageClass:     longhorn"
echo "PVC per pod:      5Gi"
echo

kubectl wait --for=condition=Ready nodes --all --timeout=180s

if ! kubectl get storageclass longhorn >/dev/null 2>&1; then
  echo "ERROR: Vault requires the Longhorn StorageClass." >&2
  echo "Install Longhorn first:" >&2
  echo "  .\\scripts\\deploy.ps1 longhorn" >&2
  exit 1
fi

echo "[1/5] Add/update HashiCorp Helm repository"
helm repo add hashicorp https://helm.releases.hashicorp.com --force-update
helm repo update

echo "[2/5] Render Vault chart"
helm template vault hashicorp/vault   --namespace vault   --version "${VAULT_CHART_VERSION}"   -f /vagrant/deployments/vault/values.yaml   >/tmp/vault-rendered.yaml

test -s /tmp/vault-rendered.yaml

echo "[3/5] Install/upgrade Vault"
# Do not use --wait here. A newly installed Vault cluster is intentionally
# uninitialized/sealed until vault-init.ps1 is run.
helm upgrade --install vault hashicorp/vault   --namespace vault   --create-namespace   --version "${VAULT_CHART_VERSION}"   -f /vagrant/deployments/vault/values.yaml   --timeout 10m

echo "[4/5] Wait for all three Vault server pods to exist and run"
for i in $(seq 1 120); do
  count="$(kubectl -n vault get pod -l app.kubernetes.io/name=vault,component=server     --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  running="$(kubectl -n vault get pod -l app.kubernetes.io/name=vault,component=server     --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  if [ "${count}" = "3" ] && [ "${running}" = "3" ]; then
    break
  fi
  sleep 3
done

count="$(kubectl -n vault get pod -l app.kubernetes.io/name=vault,component=server   --no-headers 2>/dev/null | wc -l | tr -d ' ')"
running="$(kubectl -n vault get pod -l app.kubernetes.io/name=vault,component=server   --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')"

if [ "${count}" != "3" ] || [ "${running}" != "3" ]; then
  echo "ERROR: expected three Running Vault server pods." >&2
  kubectl -n vault get pods -o wide >&2 || true
  exit 1
fi

if kubectl -n vault get deployment vault-agent-injector >/dev/null 2>&1; then
  kubectl -n vault rollout status deployment/vault-agent-injector --timeout=300s
fi

echo "[5/5] Verify PVCs and services"
kubectl -n vault get statefulset,pods,pvc,svc -o wide
echo
kubectl -n vault get pvc   -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,STORAGECLASS:.spec.storageClassName,SIZE:.spec.resources.requests.storage'

echo
echo
echo "Vault UI Service endpoints:"
kubectl -n vault get endpointslice \
  -l kubernetes.io/service-name=vault-ui \
  -o wide 2>/dev/null || true

echo
echo "Vault installation completed."
echo
echo "IMPORTANT:"
echo "  The Vault servers are expected to be uninitialized/sealed now."
echo "  The UI Service is reachable before initialization/unseal."
echo "  Initialize and form the Raft cluster from Windows with:"
echo "    .\\scripts\\vault-init.ps1"
echo
echo "After a VM/Vault restart, unseal with:"
echo "    .\\scripts\\vault-unseal.ps1"
