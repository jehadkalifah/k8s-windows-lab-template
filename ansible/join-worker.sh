#!/usr/bin/env bash
set -euo pipefail

MASTER_IP="192.168.56.10"
TOKEN_FILE="/vagrant/.k3s-token"

for i in $(seq 1 60); do
  if [ -s "${TOKEN_FILE}" ]; then
    break
  fi
  sleep 2
done

if [ ! -s "${TOKEN_FILE}" ]; then
  echo "K3s token was not created by the master." >&2
  exit 1
fi

TOKEN="$(cat "${TOKEN_FILE}")"

if ! systemctl is-active --quiet k3s-agent; then
  curl -sfL https://get.k3s.io | \
    INSTALL_K3S_VERSION=v1.36.1+k3s1 \
    K3S_URL="https://${MASTER_IP}:6443" \
    K3S_TOKEN="${TOKEN}" \
    K3S_NODE_NAME="$(hostname)" \
    sh -
fi
