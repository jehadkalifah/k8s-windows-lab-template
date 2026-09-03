#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

VELERO_CHART_VERSION="${VELERO_CHART_VERSION:-12.1.0}"
VELERO_VERSION="v1.18.1"

echo "===================================================="
echo " Stage 2 - Velero + MinIO"
echo "===================================================="
echo "Velero chart: ${VELERO_CHART_VERSION}"
echo "Velero app:   ${VELERO_VERSION}"
echo "AWS plugin:   v1.14.2"
echo

kubectl wait --for=condition=Ready nodes --all --timeout=180s

if ! kubectl get storageclass longhorn >/dev/null 2>&1; then
  echo "ERROR: Longhorn is required for the local MinIO PVC." >&2
  echo "Install Longhorn first: .\\scripts\\deploy.ps1 longhorn" >&2
  exit 1
fi

echo "[1/6] Deploy MinIO"
kubectl apply -f /vagrant/deployments/velero/manifests/minio.yaml
kubectl -n velero rollout status deployment/minio --timeout=300s

echo "[2/6] Create Velero bucket"
kubectl -n velero delete job minio-setup --ignore-not-found=true
kubectl apply -f /vagrant/deployments/velero/manifests/minio-setup-job.yaml
kubectl -n velero wait --for=condition=complete job/minio-setup --timeout=180s

echo "[3/6] Install Velero CLI if required"
CURRENT=""
if command -v velero >/dev/null 2>&1; then
  CURRENT="$(velero version --client-only 2>/dev/null | awk '/Version:/ {print $2}' | head -1 || true)"
fi
if [ "${CURRENT}" != "${VELERO_VERSION}" ]; then
  TMP="$(mktemp -d)"
  curl -fsSL -o "${TMP}/velero.tar.gz" \
    "https://github.com/vmware-tanzu/velero/releases/download/${VELERO_VERSION}/velero-${VELERO_VERSION}-linux-amd64.tar.gz"
  tar -xzf "${TMP}/velero.tar.gz" -C "${TMP}"
  install -m 0755 "${TMP}/velero-${VELERO_VERSION}-linux-amd64/velero" /usr/local/bin/velero
  rm -rf "${TMP}"
fi

echo "[4/6] Install Velero"
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts --force-update
helm repo update

helm template velero vmware-tanzu/velero \
  --namespace velero \
  --version "${VELERO_CHART_VERSION}" \
  -f /vagrant/deployments/velero/values.yaml \
  >/tmp/velero-rendered.yaml
test -s /tmp/velero-rendered.yaml

helm upgrade --install velero vmware-tanzu/velero \
  --namespace velero \
  --create-namespace \
  --version "${VELERO_CHART_VERSION}" \
  -f /vagrant/deployments/velero/values.yaml \
  --wait \
  --timeout 10m

echo "[5/6] Wait for Velero"
kubectl -n velero rollout status deployment/velero --timeout=300s
if kubectl -n velero get daemonset node-agent >/dev/null 2>&1; then
  kubectl -n velero rollout status daemonset/node-agent --timeout=300s
fi

echo "[6/6] Verify BackupStorageLocation"
for i in $(seq 1 60); do
  PHASE="$(kubectl -n velero get backupstoragelocation default -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  [ "${PHASE}" = "Available" ] && break
  sleep 3
done

kubectl -n velero get backupstoragelocation
kubectl -n velero get pods -o wide

echo
echo "MinIO console:"
echo "  kubectl -n velero port-forward svc/minio 9001:9001"
echo "  http://127.0.0.1:9001"
echo "  minio / minio123"
echo
echo "IMPORTANT: local MinIO is inside the lab and does not survive full VM destroy."
