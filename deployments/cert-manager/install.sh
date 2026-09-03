#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.21.1}"

echo "===================================================="
echo " Stage 2 - cert-manager"
echo "===================================================="
echo "cert-manager: ${CERT_MANAGER_VERSION}"
echo

echo "[1/6] Validate base Kubernetes cluster"
kubectl wait --for=condition=Ready nodes --all --timeout=180s

echo "[2/6] Install Helm if required"
if ! command -v helm >/dev/null 2>&1; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi
helm version --short

echo "[3/6] Install cert-manager from the official OCI Helm chart"
helm upgrade --install cert-manager \
  oci://quay.io/jetstack/charts/cert-manager \
  --version "${CERT_MANAGER_VERSION}" \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true \
  --wait \
  --timeout 5m

echo "[4/6] Wait for cert-manager workloads"
kubectl -n cert-manager rollout status deployment/cert-manager --timeout=180s
kubectl -n cert-manager rollout status deployment/cert-manager-cainjector --timeout=180s
kubectl -n cert-manager rollout status deployment/cert-manager-webhook --timeout=180s

echo "[5/6] Verify cert-manager CRDs"
for crd in \
  certificates.cert-manager.io \
  certificaterequests.cert-manager.io \
  issuers.cert-manager.io \
  clusterissuers.cert-manager.io; do
  kubectl wait --for=condition=Established "crd/${crd}" --timeout=120s
done

echo "[6/6] Apply local self-signed verification objects"
kubectl apply -f /vagrant/deployments/cert-manager/manifests/selfsigned-test.yaml

for i in $(seq 1 60); do
  READY="$(kubectl -n cert-manager-test get certificate lab-test-cert \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
  if [ "${READY}" = "True" ]; then
    break
  fi
  sleep 2
done

READY="$(kubectl -n cert-manager-test get certificate lab-test-cert \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"

if [ "${READY}" != "True" ]; then
  echo "cert-manager installed, but the verification Certificate is not Ready." >&2
  kubectl -n cert-manager-test describe certificate lab-test-cert || true
  exit 1
fi

echo
echo "=== cert-manager pods ==="
kubectl -n cert-manager get pods
echo
echo "=== verification certificate ==="
kubectl -n cert-manager-test get issuer,certificate,secret
echo
echo "cert-manager deployment completed successfully."
