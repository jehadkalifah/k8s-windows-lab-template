#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
PURGE_PREREQUISITES="${PURGE_PREREQUISITES:-0}"

kubectl delete -f /vagrant/deployments/istio/manifests/demo.yaml --ignore-not-found=true || true
kubectl delete -f /vagrant/deployments/istio/manifests/gateway.yaml --ignore-not-found=true || true

helm uninstall istiod -n istio-system 2>/dev/null || true
helm uninstall istio-base -n istio-system 2>/dev/null || true
kubectl delete namespace istio-system --ignore-not-found=true || true
kubectl delete namespace istio-ingress --ignore-not-found=true || true

if [ "${PURGE_PREREQUISITES}" = "1" ]; then
  helm uninstall metallb -n metallb-system 2>/dev/null || true
  kubectl delete namespace metallb-system --ignore-not-found=true || true
  kubectl delete -f \
    "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.0/standard-install.yaml" \
    --ignore-not-found=true || true
else
  echo "Keeping Gateway API CRDs and MetalLB for future Stage 2 deployments."
fi
