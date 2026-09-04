#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "=== Keycloak Operator ==="
kubectl -n keycloak get deployment keycloak-operator -o wide 2>/dev/null || true
kubectl -n keycloak get pods -l name=keycloak-operator -o wide 2>/dev/null || \
  kubectl -n keycloak get pods -o wide | grep -E 'keycloak-operator|NAME' || true

echo
echo "=== Keycloak CR ==="
kubectl -n keycloak get keycloak keycloak 2>/dev/null || true

echo
echo "=== Keycloak workload/service ==="
kubectl -n keycloak get deployment,pod,svc -o wide 2>/dev/null || true

echo
echo "=== PostgreSQL ==="
kubectl -n keycloak get statefulset keycloak-postgres -o wide 2>/dev/null || true
kubectl -n keycloak get pod -l app=keycloak-postgres -o wide 2>/dev/null || true

echo
echo "=== Persistent storage ==="
kubectl -n keycloak get pvc \
  -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,STORAGECLASS:.spec.storageClassName,SIZE:.spec.resources.requests.storage,VOLUME:.spec.volumeName' \
  2>/dev/null || true

echo
echo "=== Monitoring ==="
kubectl -n keycloak get servicemonitor keycloak -o wide 2>/dev/null || true

echo
echo "=== Bootstrap admin secret ==="
if kubectl -n keycloak get secret keycloak-initial-admin >/dev/null 2>&1; then
  echo "keycloak-initial-admin exists."
  echo "Retrieve credentials from Windows:"
  echo "  .\\scripts\\keycloak-admin.ps1"
else
  echo "keycloak-initial-admin not found yet or has already been removed."
fi

echo
echo "Expected public path:"
echo "  /keycloak"
