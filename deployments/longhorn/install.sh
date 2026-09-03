#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

LONGHORN_VERSION="${LONGHORN_VERSION:-1.12.1}"

echo "===================================================="
echo " Stage 2 - Longhorn"
echo "===================================================="
echo "Longhorn: ${LONGHORN_VERSION}"
echo

echo "[1/4] Validate cluster"
kubectl wait --for=condition=Ready nodes --all --timeout=180s

echo "[2/4] Install Longhorn"
helm repo add longhorn https://charts.longhorn.io --force-update
helm repo update

helm template longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --version "${LONGHORN_VERSION}" \
  --set persistence.defaultClass=true \
  --set persistence.defaultClassReplicaCount=2 \
  --set service.ui.type=ClusterIP \
  >/tmp/longhorn-rendered.yaml

test -s /tmp/longhorn-rendered.yaml

helm upgrade --install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace \
  --version "${LONGHORN_VERSION}" \
  --set persistence.defaultClass=true \
  --set persistence.defaultClassReplicaCount=2 \
  --set service.ui.type=ClusterIP \
  --wait \
  --timeout 10m

echo "[3/4] Wait for Longhorn components"
kubectl -n longhorn-system rollout status daemonset/longhorn-manager --timeout=300s
kubectl -n longhorn-system rollout status deployment/longhorn-driver-deployer --timeout=300s
if kubectl -n longhorn-system get deployment longhorn-ui >/dev/null 2>&1; then
  kubectl -n longhorn-system rollout status deployment/longhorn-ui --timeout=300s
fi

echo "[4/4] Verify StorageClass"
kubectl get storageclass longhorn
kubectl -n longhorn-system get pods -o wide

echo
echo "Longhorn deployment completed."
echo "UI:"
echo "  kubectl -n longhorn-system port-forward svc/longhorn-frontend 8081:80"
