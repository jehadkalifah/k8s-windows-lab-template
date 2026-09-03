#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "=== Gateway API CRDs ==="
kubectl get crd gatewayclasses.gateway.networking.k8s.io \
  gateways.gateway.networking.k8s.io \
  httproutes.gateway.networking.k8s.io

echo
echo "=== Helm releases ==="
helm list -A

echo
echo "=== GatewayClass ==="
kubectl get gatewayclass

echo
echo "=== Istio ==="
kubectl -n istio-system get deployment,pod

echo
echo "=== MetalLB ==="
kubectl -n metallb-system get deployment,daemonset,pod
kubectl -n metallb-system get ipaddresspool,l2advertisement

echo
echo "=== Gateway ==="
kubectl -n istio-ingress get gateway,svc -o wide

echo
echo "=== Demo / HTTPRoute ==="
kubectl -n demo get deployment,pod,svc,httproute -o wide

GATEWAY_IP="$(kubectl -n istio-ingress get svc \
  -l gateway.networking.k8s.io/gateway-name=public-gateway \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"

echo
if [ -n "${GATEWAY_IP}" ]; then
  echo "Ingress URL: http://${GATEWAY_IP}/"
else
  echo "Ingress external IP: <pending>"
fi
