#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "=== Helm release ==="
helm list -n reloader || true

echo
echo "=== Reloader deployment / pods ==="
kubectl -n reloader get deployment,pods -o wide || true

echo
echo "=== Reloader arguments ==="
kubectl -n reloader get deployment reloader-reloader \
  -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{.}{"\n"}{end}' \
  2>/dev/null || true

echo
echo "=== Expected policy ==="
echo "reloadStrategy: annotations"
echo "autoReloadAll: false"
echo "ignoreJobs: true"
echo "ignoreCronJobs: true"

echo
echo "=== Opted-in workloads ==="
kubectl get deployment,statefulset,daemonset -A \
  -o jsonpath='{range .items[?(@.metadata.annotations.reloader\.stakater\.com/auto=="true")]}{.kind}{"\t"}{.metadata.namespace}{"/"}{.metadata.name}{"\n"}{end}' \
  2>/dev/null || true

echo
echo "Reloader has no browser UI and requires no PVC."
