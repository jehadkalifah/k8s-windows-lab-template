#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

for item in \
  /vagrant/deployments/publishing/routes/demo.yaml \
  /vagrant/deployments/publishing/routes/monitoring.yaml \
  /vagrant/deployments/publishing/routes/argocd.yaml \
  /vagrant/deployments/publishing/routes/minio.yaml
do
  kubectl delete -f "${item}" --ignore-not-found=true || true
done

echo "Shared publishing HTTPRoutes removed. The Gateway and workloads were kept."

kubectl -n longhorn-system delete httproute longhorn-entry longhorn-ui --ignore-not-found=true || true

kubectl -n vault delete httproute vault-entry vault-ui --ignore-not-found=true || true
