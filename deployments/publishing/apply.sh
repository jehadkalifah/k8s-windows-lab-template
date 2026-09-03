#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

COMPONENT="${1:-all}"
GATEWAY_NAMESPACE="${GATEWAY_NAMESPACE:-istio-ingress}"
GATEWAY_NAME="${GATEWAY_NAME:-public-gateway}"

gateway_ready() {
  kubectl -n "${GATEWAY_NAMESPACE}" get gateway "${GATEWAY_NAME}" >/dev/null 2>&1 &&
  [ "$(kubectl -n "${GATEWAY_NAMESPACE}" get gateway "${GATEWAY_NAME}" -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || true)" = "True" ]
}

gateway_ip() {
  kubectl -n "${GATEWAY_NAMESPACE}" get gateway "${GATEWAY_NAME}" \
    -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true
}

apply_if_service() {
  local namespace="$1"
  local service="$2"
  local manifest="$3"

  if kubectl -n "${namespace}" get service "${service}" >/dev/null 2>&1; then
    kubectl apply -f "${manifest}"
  else
    echo "SKIP: ${namespace}/${service} is not installed."
  fi
}

configure_demo() {
  apply_if_service demo hello /vagrant/deployments/publishing/routes/demo.yaml
}

configure_longhorn() {
  local ip="$1"

  if ! kubectl -n longhorn-system get service longhorn-frontend >/dev/null 2>&1; then
    echo "SKIP: Longhorn is not installed."
    return
  fi

  local ip_dash="${ip//./-}"
  local host="${LONGHORN_PUBLISH_HOST:-longhorn.${ip_dash}.nip.io}"
  local rendered="/tmp/longhorn-publishing.yaml"

  if [ -z "${host}" ]; then
    echo "ERROR: calculated Longhorn publishing hostname is empty." >&2
    exit 1
  fi

  echo "Reconciling Longhorn publishing:"
  echo "  Gateway IP: ${ip}"
  echo "  Hostname:   ${host}"

  sed "s/__LONGHORN_HOST__/${host}/g" \
    /vagrant/deployments/publishing/routes/longhorn.yaml \
    > "${rendered}"

  if grep -q '__LONGHORN_HOST__' "${rendered}"; then
    echo "ERROR: unresolved __LONGHORN_HOST__ placeholder remains." >&2
    exit 1
  fi

  kubectl -n longhorn-system delete httproute \
    longhorn-entry longhorn-ui \
    --ignore-not-found=true \
    --wait=true

  kubectl apply -f "${rendered}"

  local live_host=""
  for i in $(seq 1 20); do
    live_host="$(kubectl -n longhorn-system get httproute longhorn-ui \
      -o jsonpath='{.spec.hostnames[0]}' 2>/dev/null || true)"
    [ "${live_host}" = "${host}" ] && break
    sleep 1
  done

  if [ "${live_host}" != "${host}" ]; then
    echo "ERROR: Longhorn HTTPRoute hostname reconciliation failed." >&2
    echo "Expected: ${host}" >&2
    echo "Live:     ${live_host:-<empty>}" >&2
    kubectl -n longhorn-system get httproute longhorn-ui -o yaml >&2 || true
    exit 1
  fi

  echo
  echo "Live Longhorn HTTPRoutes:"
  kubectl -n longhorn-system get httproute longhorn-entry longhorn-ui -o wide

  echo
  echo "Longhorn entry: http://${ip}/longhorn"
  echo "Longhorn UI:    http://${host}/"
}


configure_vault() {
  local ip="$1"

  if ! kubectl -n vault get service vault-ui >/dev/null 2>&1; then
    echo "SKIP: Vault is not installed."
    return
  fi

  local ip_dash="${ip//./-}"
  local host="${VAULT_PUBLISH_HOST:-vault.${ip_dash}.nip.io}"
  local rendered="/tmp/vault-publishing.yaml"

  if [ -z "${host}" ]; then
    echo "ERROR: calculated Vault publishing hostname is empty." >&2
    exit 1
  fi

  echo "Reconciling Vault publishing:"
  echo "  Gateway IP: ${ip}"
  echo "  Hostname:   ${host}"

  sed "s/__VAULT_HOST__/${host}/g" \
    /vagrant/deployments/publishing/routes/vault.yaml \
    > "${rendered}"

  if grep -q '__VAULT_HOST__' "${rendered}"; then
    echo "ERROR: unresolved __VAULT_HOST__ placeholder remains." >&2
    exit 1
  fi

  kubectl -n vault delete httproute \
    vault-entry vault-ui \
    --ignore-not-found=true \
    --wait=true

  kubectl apply -f "${rendered}"

  local live_host=""
  for i in $(seq 1 20); do
    live_host="$(kubectl -n vault get httproute vault-ui \
      -o jsonpath='{.spec.hostnames[0]}' 2>/dev/null || true)"
    [ "${live_host}" = "${host}" ] && break
    sleep 1
  done

  if [ "${live_host}" != "${host}" ]; then
    echo "ERROR: Vault HTTPRoute hostname reconciliation failed." >&2
    echo "Expected: ${host}" >&2
    echo "Live:     ${live_host:-<empty>}" >&2
    kubectl -n vault get httproute vault-ui -o yaml >&2 || true
    exit 1
  fi

  echo
  echo "Vault entry: http://${ip}/vault"
  echo "Vault UI:    http://${host}/"
}

configure_monitoring() {
  if ! kubectl -n monitoring get service monitoring-grafana >/dev/null 2>&1; then
    echo "SKIP: monitoring is not installed."
    return
  fi

  local ip="$1"

  # Grafana requires its public subpath in root_url when served from /grafana.
  kubectl -n monitoring set env deployment/monitoring-grafana \
    GF_SERVER_ROOT_URL="http://${ip}/grafana/" \
    GF_SERVER_SERVE_FROM_SUB_PATH="true" >/dev/null

  # Prometheus and Alertmanager generate links from these external URL values.
  if kubectl -n monitoring get prometheus monitoring-kube-prometheus-prometheus >/dev/null 2>&1; then
    kubectl -n monitoring patch prometheus monitoring-kube-prometheus-prometheus \
      --type merge \
      -p "{\"spec\":{\"externalUrl\":\"http://${ip}/prometheus\",\"routePrefix\":\"/prometheus\"}}" >/dev/null
  fi

  if kubectl -n monitoring get alertmanager monitoring-kube-prometheus-alertmanager >/dev/null 2>&1; then
    kubectl -n monitoring patch alertmanager monitoring-kube-prometheus-alertmanager \
      --type merge \
      -p "{\"spec\":{\"externalUrl\":\"http://${ip}/alertmanager\",\"routePrefix\":\"/alertmanager\"}}" >/dev/null
  fi

  kubectl apply -f /vagrant/deployments/publishing/routes/monitoring.yaml
  kubectl -n monitoring rollout status deployment/monitoring-grafana --timeout=180s || true
}

configure_argocd() {
  if ! kubectl -n argocd get service argocd-server >/dev/null 2>&1; then
    echo "SKIP: Argo CD is not installed."
    return
  fi

  # Argo CD officially supports non-root deployment through basehref/rootpath.
  kubectl -n argocd patch configmap argocd-cmd-params-cm --type merge \
    -p '{"data":{"server.insecure":"true","server.basehref":"/argocd","server.rootpath":"/argocd"}}' >/dev/null

  kubectl -n argocd rollout restart deployment/argocd-server >/dev/null
  kubectl -n argocd rollout status deployment/argocd-server --timeout=180s

  kubectl apply -f /vagrant/deployments/publishing/routes/argocd.yaml
}

configure_velero() {
  if ! kubectl -n velero get service minio >/dev/null 2>&1; then
    echo "SKIP: Velero/MinIO is not installed."
    return
  fi

  local ip="$1"

  # MinIO Console supports reverse-proxy publishing when the external browser
  # URL is declared. The S3 API remains internal and is NOT published at a
  # path because AWS Signature V4 does not support an arbitrary S3 URL prefix.
  kubectl -n velero set env deployment/minio \
    MINIO_BROWSER_REDIRECT_URL="http://${ip}/minio/" >/dev/null

  kubectl -n velero rollout status deployment/minio --timeout=180s
  kubectl apply -f /vagrant/deployments/publishing/routes/minio.yaml
}

if ! gateway_ready; then
  echo "Publishing skipped: ${GATEWAY_NAMESPACE}/${GATEWAY_NAME} is not Programmed."
  echo "Install/reconcile Istio first:"
  echo "  .\\scripts\\deploy.ps1 istio"
  echo "Then publish:"
  echo "  .\\scripts\\publish.ps1 all"
  exit 0
fi

IP="$(gateway_ip)"
if [ -z "${IP}" ]; then
  echo "ERROR: Gateway is Programmed but has no address." >&2
  exit 1
fi

echo "Shared Gateway: ${GATEWAY_NAMESPACE}/${GATEWAY_NAME}"
echo "Gateway IP:     ${IP}"
echo

case "${COMPONENT}" in
  demo)
    configure_demo
    ;;
  longhorn)
    configure_longhorn "${IP}"
    ;;
  vault)
    configure_vault "${IP}"
    ;;
  monitoring)
    configure_monitoring "${IP}"
    ;;
  argocd)
    configure_argocd
    ;;
  velero|minio)
    configure_velero "${IP}"
    ;;
  istio)
    configure_demo
    ;;
  all)
    configure_demo
    configure_longhorn "${IP}"
    configure_vault "${IP}"
    configure_monitoring "${IP}"
    configure_argocd
    configure_velero "${IP}"
    ;;
  *)
    echo "Unknown publishing component: ${COMPONENT}" >&2
    exit 1
    ;;
esac

echo
echo "Publishing reconciliation complete."
echo "Run:"
echo "  .\\scripts\\publishing-status.ps1"
