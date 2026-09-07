#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

CONFIG_FILE="/etc/rancher/k3s/config.yaml"
BACKUP_FILE="/etc/rancher/k3s/config.yaml.before-local-storage-enable"

echo "=== K3s local storage ==="

if kubectl get storageclass local-path >/dev/null 2>&1; then
  PROVISIONER="$(kubectl get storageclass local-path -o jsonpath='{.provisioner}' 2>/dev/null || true)"

  if [ "${PROVISIONER}" != "rancher.io/local-path" ]; then
    echo "ERROR: local-path exists with unexpected provisioner: ${PROVISIONER:-<empty>}" >&2
    exit 1
  fi

  echo "local-path already available."
  kubectl get storageclass local-path
  exit 0
fi

echo "local-path StorageClass is missing."

if [ ! -f "${CONFIG_FILE}" ]; then
  echo "ERROR: ${CONFIG_FILE} does not exist." >&2
  exit 1
fi

if grep -Eq '^[[:space:]]*-[[:space:]]*local-storage[[:space:]]*$' "${CONFIG_FILE}"; then
  echo "Found local-storage in the K3s disable list."
  echo "Enabling the bundled K3s Local Path Provisioner..."

  if [ ! -f "${BACKUP_FILE}" ]; then
    cp -a "${CONFIG_FILE}" "${BACKUP_FILE}"
    chmod 600 "${BACKUP_FILE}" || true
    echo "Saved one-time backup:"
    echo "  ${BACKUP_FILE}"
  fi

  # Remove only the exact YAML list item for local-storage.
  # Keep Traefik and ServiceLB disabled.
  sed -i -E '/^[[:space:]]*-[[:space:]]*local-storage[[:space:]]*$/d' "${CONFIG_FILE}"
else
  echo "local-storage is not currently listed under K3s disable."
  echo "Restarting K3s once so packaged components are reconciled."
fi

echo
echo "Current K3s disable block:"
awk '
  /^disable:/ {print; in_disable=1; next}
  in_disable && /^[[:space:]]*-/ {print; next}
  in_disable {exit}
' "${CONFIG_FILE}" || true

echo
echo "Restarting K3s server..."
systemctl restart k3s

echo "Waiting for Kubernetes API..."
API_READY=0
for i in $(seq 1 120); do
  if kubectl get --raw=/readyz >/dev/null 2>&1; then
    API_READY=1
    break
  fi
  sleep 2
done

if [ "${API_READY}" != "1" ]; then
  echo "ERROR: K3s API did not become Ready after enabling local-storage." >&2
  systemctl --no-pager --full status k3s >&2 || true
  journalctl -u k3s -n 100 --no-pager >&2 || true
  exit 1
fi

echo "Waiting for cluster nodes..."
kubectl wait --for=condition=Ready nodes --all --timeout=240s

echo "Waiting for K3s local-path StorageClass..."
LOCAL_READY=0
for i in $(seq 1 120); do
  if kubectl get storageclass local-path >/dev/null 2>&1; then
    PROVISIONER="$(kubectl get storageclass local-path -o jsonpath='{.provisioner}' 2>/dev/null || true)"
    if [ "${PROVISIONER}" = "rancher.io/local-path" ]; then
      LOCAL_READY=1
      break
    fi
  fi
  sleep 2
done

if [ "${LOCAL_READY}" != "1" ]; then
  echo "ERROR: K3s did not recreate the local-path StorageClass." >&2
  echo >&2
  echo "K3s config:" >&2
  sed -n '1,120p' "${CONFIG_FILE}" >&2 || true
  echo >&2
  echo "Kube-system local-path resources:" >&2
  kubectl -n kube-system get deploy,pod,cm 2>/dev/null | grep -i local-path >&2 || true
  echo >&2
  echo "Recent K3s logs:" >&2
  journalctl -u k3s -n 120 --no-pager >&2 || true
  exit 1
fi

echo
echo "K3s local storage is enabled."
kubectl get storageclass local-path -o wide

if kubectl -n kube-system get deployment local-path-provisioner >/dev/null 2>&1; then
  kubectl -n kube-system rollout status deployment/local-path-provisioner --timeout=180s
  kubectl -n kube-system get deployment,pods -l app=local-path-provisioner -o wide || true
else
  kubectl -n kube-system get pods -o wide | grep -i local-path || true
fi
