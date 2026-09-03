#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

ISTIO_VERSION="${ISTIO_VERSION:-1.31.0}"
GATEWAY_API_VERSION="${GATEWAY_API_VERSION:-v1.6.0}"
METALLB_VERSION="${METALLB_VERSION:-0.16.1}"
METALLB_POOL_START="${METALLB_POOL_START:-192.168.100.240}"
METALLB_POOL_END="${METALLB_POOL_END:-192.168.100.245}"

echo "===================================================="
echo " Stage 2 - Istio ingress"
echo "===================================================="
echo "Istio:       ${ISTIO_VERSION}"
echo "Gateway API: ${GATEWAY_API_VERSION}"
echo "MetalLB:     ${METALLB_VERSION}"
echo "MetalLB IPs: ${METALLB_POOL_START}-${METALLB_POOL_END}"
echo

echo "[1/10] Validate the base cluster"
kubectl wait --for=condition=Ready nodes --all --timeout=180s
test "$(kubectl get nodes --no-headers | wc -l | tr -d ' ')" -eq 3

echo "[2/10] Install Helm if required"
if ! command -v helm >/dev/null 2>&1; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi
helm version --short

echo "[3/10] Install Gateway API standard CRDs"
kubectl apply --server-side=true \
  -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"

for crd in \
  gatewayclasses.gateway.networking.k8s.io \
  gateways.gateway.networking.k8s.io \
  httproutes.gateway.networking.k8s.io; do
  kubectl wait --for=condition=Established "crd/${crd}" --timeout=120s
done

echo "[4/10] Install MetalLB for L2 mode"
helm repo add metallb https://metallb.github.io/metallb --force-update
helm repo update

# Lab-specific choices:
# - L2 only, so FRR-K8s is not required.
# - Pin the controller/webhook to k3s-master. The kube-apiserver also runs
#   on k3s-master, which avoids cross-node webhook connectivity problems
#   in local VirtualBox/K3s labs while speakers still run on every node.
helm upgrade --install metallb metallb/metallb \
  --namespace metallb-system \
  --create-namespace \
  --version "${METALLB_VERSION}" \
  --set frrk8s.enabled=false \
  --set-string controller.nodeSelector."kubernetes\.io/hostname"=k3s-master \
  --wait \
  --timeout 5m

kubectl -n metallb-system rollout status deployment/metallb-controller --timeout=180s
kubectl -n metallb-system rollout status daemonset/metallb-speaker --timeout=180s

echo "[5/10] Wait for MetalLB validating webhook"
for i in $(seq 1 60); do
  ENDPOINTS="$(kubectl -n metallb-system get endpoints metallb-webhook-service \
    -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || true)"
  CERT_READY="$(kubectl -n metallb-system get secret metallb-webhook-cert \
    -o name 2>/dev/null || true)"

  # Chart versions may use webhook-server-cert instead.
  if [ -z "${CERT_READY}" ]; then
    CERT_READY="$(kubectl -n metallb-system get secret webhook-server-cert \
      -o name 2>/dev/null || true)"
  fi

  if [ -n "${ENDPOINTS}" ] && [ -n "${CERT_READY}" ]; then
    break
  fi
  sleep 2
done

kubectl -n metallb-system get svc metallb-webhook-service
kubectl -n metallb-system get endpoints metallb-webhook-service

WEBHOOK_IP="$(kubectl -n metallb-system get svc metallb-webhook-service \
  -o jsonpath='{.spec.clusterIP}')"

if [ -z "${WEBHOOK_IP}" ]; then
  echo "MetalLB webhook Service has no ClusterIP." >&2
  exit 1
fi

echo "Testing webhook Service from k3s-master: ${WEBHOOK_IP}:443"
WEBHOOK_OK="0"
for i in $(seq 1 30); do
  RESPONSE="$(curl -ksS --max-time 5 \
    "https://${WEBHOOK_IP}/validate-metallb-io-v1beta1-ipaddresspool?timeout=10s" \
    2>/dev/null || true)"

  # A GET request is intentionally invalid for an admission webhook.
  # Receiving a JSON admission response proves the Service/TLS path is reachable.
  if echo "${RESPONSE}" | grep -q '"response"'; then
    WEBHOOK_OK="1"
    break
  fi

  echo "Webhook not reachable yet; retry ${i}/30..."
  sleep 3
done

if [ "${WEBHOOK_OK}" != "1" ]; then
  echo "ERROR: MetalLB webhook Service is not reachable from k3s-master." >&2
  echo
  echo "Diagnostics:" >&2
  kubectl -n metallb-system get pod -o wide >&2 || true
  kubectl -n metallb-system get svc,endpoints >&2 || true
  kubectl -n metallb-system logs deployment/metallb-controller --tail=100 >&2 || true
  exit 1
fi

echo "[6/10] Configure MetalLB IPAddressPool and L2Advertisement"
cat >/tmp/metallb-l2.yaml <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: lan-pool
  namespace: metallb-system
spec:
  addresses:
    - ${METALLB_POOL_START}-${METALLB_POOL_END}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: lan-l2
  namespace: metallb-system
spec:
  ipAddressPools:
    - lan-pool
EOF

APPLY_OK="0"
for i in $(seq 1 12); do
  if kubectl apply -f /tmp/metallb-l2.yaml; then
    APPLY_OK="1"
    break
  fi

  echo "MetalLB CR apply failed; waiting for webhook and retrying ${i}/12..."
  sleep 5
done

if [ "${APPLY_OK}" != "1" ]; then
  echo "ERROR: MetalLB CRs could not be created after retries." >&2
  kubectl -n metallb-system get pod -o wide >&2 || true
  kubectl -n metallb-system get svc,endpoints >&2 || true
  kubectl get validatingwebhookconfiguration metallb-webhook-configuration -o yaml >&2 || true
  exit 1
fi

kubectl -n metallb-system get ipaddresspool,l2advertisement

echo "[7/10] Install Istio base"
helm repo add istio https://blob.istio.io/istio-release/charts --force-update
helm repo update

helm upgrade --install istio-base istio/base \
  --namespace istio-system \
  --create-namespace \
  --version "${ISTIO_VERSION}" \
  --wait \
  --timeout 5m

echo "[8/10] Validate and install istiod"

# For Helm-based standard Istio installation, install the istiod chart with
# its chart defaults. Do not pass the istioctl-oriented "minimal" component
# profile here; Istio 1.31's istiod Helm chart rejects that value.
#
# Run a render-only preflight first so chart/value errors are caught before
# Helm changes the cluster.
helm template istiod istio/istiod \
  --namespace istio-system \
  --version "${ISTIO_VERSION}" \
  >/tmp/istiod-rendered.yaml

test -s /tmp/istiod-rendered.yaml

helm upgrade --install istiod istio/istiod \
  --namespace istio-system \
  --version "${ISTIO_VERSION}" \
  --wait \
  --timeout 5m

kubectl -n istio-system rollout status deployment/istiod --timeout=180s

echo "[9/10] Create Istio Gateway, demo app and HTTPRoute"
for i in $(seq 1 60); do
  kubectl get gatewayclass istio >/dev/null 2>&1 && break
  sleep 2
done
kubectl get gatewayclass istio >/dev/null

kubectl apply -f /vagrant/deployments/istio/manifests/gateway.yaml
kubectl apply -f /vagrant/deployments/istio/manifests/demo.yaml
kubectl -n demo rollout status deployment/hello --timeout=180s
kubectl -n istio-ingress wait \
  --for=condition=Programmed \
  gateway/public-gateway \
  --timeout=180s || true

echo "[10/10] Wait for MetalLB external IP"
GATEWAY_IP=""
for i in $(seq 1 90); do
  GATEWAY_IP="$(kubectl -n istio-ingress get svc \
    -l gateway.networking.k8s.io/gateway-name=public-gateway \
    -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' \
    2>/dev/null || true)"
  [ -n "${GATEWAY_IP}" ] && break
  sleep 2
done

echo
echo "=== Gateway API ==="
kubectl get gatewayclass
echo
echo "=== Istio ==="
kubectl -n istio-system get pods
echo
echo "=== MetalLB ==="
kubectl -n metallb-system get pods -o wide
kubectl -n metallb-system get ipaddresspool,l2advertisement
echo
echo "=== Gateway ==="
kubectl -n istio-ingress get gateway,svc -o wide
echo
echo "=== Demo / HTTPRoute ==="
kubectl -n demo get deployment,pod,svc,httproute -o wide
echo

if [ -n "${GATEWAY_IP}" ]; then
  echo "Ingress ready: http://${GATEWAY_IP}/"
  echo "Expected response: Hello from K3s + Istio Gateway API"
else
  echo "WARNING: Gateway Service EXTERNAL-IP is still pending."
  echo "Run: sudo bash /vagrant/deployments/istio/status.sh"
fi
