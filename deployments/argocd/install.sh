#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
ARGOCD_CHART_VERSION="${ARGOCD_CHART_VERSION:-10.4.0}"

echo "===================================================="
echo " Stage 2 - Argo CD"
echo "===================================================="
echo "Argo CD chart: ${ARGOCD_CHART_VERSION}"
echo

kubectl wait --for=condition=Ready nodes --all --timeout=180s

helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm repo update

helm template argocd argo/argo-cd \
  --namespace argocd \
  --version "${ARGOCD_CHART_VERSION}" \
  -f /vagrant/deployments/argocd/values.yaml \
  >/tmp/argocd-rendered.yaml

test -s /tmp/argocd-rendered.yaml

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --version "${ARGOCD_CHART_VERSION}" \
  -f /vagrant/deployments/argocd/values.yaml \
  --wait \
  --timeout 10m

kubectl -n argocd get pods -o wide
kubectl -n argocd get svc

echo
echo "Argo CD UI:"
echo "  kubectl -n argocd port-forward svc/argocd-server 8080:443"
echo "  https://127.0.0.1:8080"
echo
echo "Username: admin"
echo "Password command:"
echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
