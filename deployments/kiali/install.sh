#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

KIALI_VERSION="${KIALI_VERSION:-2.31.0}"

echo "===================================================="
echo " Stage 2 - Kiali Operator + Kiali"
echo "===================================================="
echo "Kiali Operator/chart: ${KIALI_VERSION}"
echo "Kiali Server:         ${KIALI_VERSION}"
echo "Web root:             /kiali"
echo

kubectl wait --for=condition=Ready nodes --all --timeout=180s

echo "[1/6] Verify dependencies"
if ! kubectl -n istio-system get deployment istiod >/dev/null 2>&1; then
  echo "ERROR: Istio is required before Kiali." >&2
  echo "  .\\scripts\\deploy.ps1 istio" >&2
  exit 1
fi

if ! kubectl -n monitoring get service monitoring-kube-prometheus-prometheus >/dev/null 2>&1; then
  echo "ERROR: Prometheus from the monitoring module is required before Kiali." >&2
  echo "  .\\scripts\\deploy.ps1 monitoring" >&2
  exit 1
fi

echo "[2/6] Install Kiali Operator"
helm repo add kiali https://kiali.org/helm-charts --force-update
helm repo update

helm template kiali-operator kiali/kiali-operator \
  --namespace kiali-operator \
  --version "${KIALI_VERSION}" \
  >/tmp/kiali-operator-rendered.yaml

test -s /tmp/kiali-operator-rendered.yaml

helm upgrade --install kiali-operator kiali/kiali-operator \
  --namespace kiali-operator \
  --create-namespace \
  --version "${KIALI_VERSION}" \
  --wait \
  --timeout 10m

echo "[3/6] Wait for CRD/operator"
kubectl wait --for=condition=Established crd/kialis.kiali.io --timeout=180s
kubectl -n kiali-operator rollout status deployment/kiali-operator --timeout=300s

echo "[4/6] Render/apply Kiali CR"
GATEWAY_IP="$(kubectl -n istio-ingress get gateway public-gateway -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)"
if [ -z "${GATEWAY_IP}" ]; then
  echo "ERROR: public-gateway has no address." >&2
  exit 1
fi

sed "s/__GATEWAY_IP__/${GATEWAY_IP}/g" /vagrant/deployments/kiali/kiali.yaml >/tmp/kiali.yaml
if grep -q '__GATEWAY_IP__' /tmp/kiali.yaml; then
  echo "ERROR: Kiali CR template still contains __GATEWAY_IP__." >&2
  exit 1
fi
kubectl apply -f /tmp/kiali.yaml

echo "[5/6] Wait for Kiali Server"
for i in $(seq 1 120); do
  kubectl -n istio-system get deployment kiali >/dev/null 2>&1 && break
  sleep 2
done

if ! kubectl -n istio-system get deployment kiali >/dev/null 2>&1; then
  echo "ERROR: Kiali Operator did not create deployment/istio-system/kiali." >&2
  kubectl -n kiali-operator logs deployment/kiali-operator --tail=100 >&2 || true
  exit 1
fi
kubectl -n istio-system rollout status deployment/kiali --timeout=600s

echo "[6/6] Verify Kiali"
kubectl -n kiali-operator get pods -o wide
kubectl -n istio-system get kiali kiali
kubectl -n istio-system get deployment kiali -o wide
kubectl -n istio-system get svc kiali -o wide

echo
echo "Kiali deployment completed."
echo "Kiali PVC: none required (Kiali is stateless)."
echo "Metrics source: monitoring/Prometheus."
echo "Publish/reconcile:"
echo "  .\\scripts\\publish.ps1 kiali"
