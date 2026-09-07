#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

if ! kubectl -n harbor get secret harbor-admin-password >/dev/null 2>&1; then
  echo "Harbor admin Secret was not found." >&2
  exit 1
fi

echo "Harbor admin user: admin"
printf "Harbor admin password: "
kubectl -n harbor get secret harbor-admin-password \
  -o go-template='{{index .data "HARBOR_ADMIN_PASSWORD"}}' | base64 -d
echo
