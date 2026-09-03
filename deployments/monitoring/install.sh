#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
CHART_VERSION="${MONITORING_CHART_VERSION:-88.5.4}"

echo "===================================================="
echo " Stage 2 - Monitoring"
echo "===================================================="
echo "kube-prometheus-stack: ${CHART_VERSION}"
echo

kubectl wait --for=condition=Ready nodes --all --timeout=180s

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
helm repo update

helm template monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --version "${CHART_VERSION}" \
  -f /vagrant/deployments/monitoring/values.yaml \
  >/tmp/monitoring-rendered.yaml

test -s /tmp/monitoring-rendered.yaml

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --version "${CHART_VERSION}" \
  -f /vagrant/deployments/monitoring/values.yaml \
  --wait \
  --timeout 10m

kubectl -n monitoring get pods -o wide
kubectl -n monitoring get svc

echo
echo "Grafana:"
echo "  kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80"
echo "  admin / admin-lab"
echo
echo "Prometheus:"
echo "  kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090"
