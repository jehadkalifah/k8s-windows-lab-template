#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "=== Helm release ==="
helm list -n monitoring
echo
echo "=== Pods ==="
kubectl -n monitoring get pods -o wide
echo
echo "=== Services ==="
kubectl -n monitoring get svc
echo
echo "=== Prometheus / Alertmanager ==="
kubectl -n monitoring get prometheus,alertmanager 2>/dev/null || true
