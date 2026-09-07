#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

RELOADER_CHART_VERSION="${RELOADER_CHART_VERSION:-2.2.16}"

echo "===================================================="
echo " Stage 2 - Stakater Reloader"
echo "===================================================="
echo "Helm chart: ${RELOADER_CHART_VERSION}"
echo "App:        v1.4.21"
echo "Strategy:   annotations"
echo "Mode:       explicit workload opt-in"
echo

kubectl wait --for=condition=Ready nodes --all --timeout=180s

echo "[1/4] Add/update Stakater Helm repository"
helm repo add stakater https://stakater.github.io/stakater-charts --force-update
helm repo update

echo "[2/4] Render the pinned Reloader chart"
helm template reloader stakater/reloader   --namespace reloader   --version "${RELOADER_CHART_VERSION}"   -f /vagrant/deployments/reloader/values.yaml   >/tmp/reloader-rendered.yaml

test -s /tmp/reloader-rendered.yaml

echo "[3/4] Install/upgrade Reloader"
helm upgrade --install reloader stakater/reloader   --namespace reloader   --create-namespace   --version "${RELOADER_CHART_VERSION}"   -f /vagrant/deployments/reloader/values.yaml   --wait   --timeout 5m

echo "[4/4] Verify Reloader"
kubectl -n reloader rollout status deployment/reloader-reloader --timeout=300s
kubectl -n reloader get deployment,pods -o wide

echo
echo "Reloader deployment completed."
echo
echo "Workloads are NOT restarted globally."
echo "Opt a Deployment/StatefulSet/DaemonSet in with:"
echo '  reloader.stakater.com/auto: "true"'
echo
echo "Example:"
echo "  /vagrant/deployments/reloader/examples/workload.yaml"
