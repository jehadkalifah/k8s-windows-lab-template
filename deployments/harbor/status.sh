#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "=== Harbor Helm release ==="
helm list -n harbor || true

echo
echo "=== Harbor workloads ==="
kubectl -n harbor get deployments,statefulsets,pods -o wide || true

echo
echo "=== Harbor services ==="
kubectl -n harbor get svc -o wide || true

echo
echo "=== K3s local-path StorageClass ==="
kubectl get storageclass local-path \
  -o custom-columns='NAME:.metadata.name,PROVISIONER:.provisioner,RECLAIM:.reclaimPolicy,BINDING:.volumeBindingMode' \
  2>/dev/null || true


echo
echo "=== K3s Local Path Provisioner ==="
kubectl -n kube-system get deployment local-path-provisioner -o wide 2>/dev/null || true
kubectl -n kube-system get pods -o wide 2>/dev/null | grep -i local-path || true

echo
echo "=== Harbor PVCs ==="
kubectl -n harbor get pvc \
  -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,STORAGECLASS:.spec.storageClassName,SIZE:.spec.resources.requests.storage,VOLUME:.spec.volumeName' \
  2>/dev/null || true

echo
echo "=== Harbor PV node affinity ==="
for pv in $(kubectl -n harbor get pvc \
  -o jsonpath='{range .items[*]}{.spec.volumeName}{"\n"}{end}' 2>/dev/null); do

  [ -z "${pv}" ] && continue

  phase="$(kubectl get pv "${pv}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  sc="$(kubectl get pv "${pv}" -o jsonpath='{.spec.storageClassName}' 2>/dev/null || true)"
  node="$(kubectl get pv "${pv}" \
    -o jsonpath='{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]}' \
    2>/dev/null || true)"

  echo "${pv}: phase=${phase:-unknown} storageClass=${sc:-unknown} node=${node:-not-bound-yet}"
done

echo
echo "=== Harbor storage validation ==="
BAD_SC="$(kubectl -n harbor get pvc \
  -o jsonpath='{range .items[?(@.spec.storageClassName!="local-path")]}{.metadata.name}{"="}{.spec.storageClassName}{"\n"}{end}' \
  2>/dev/null || true)"

if [ -n "${BAD_SC}" ]; then
  echo "ERROR: Harbor PVCs not using local-path:"
  echo "${BAD_SC}"
else
  echo "OK: all Harbor PVCs use local-path."
fi

echo
echo "=== Harbor publishing ==="
if kubectl -n harbor get httproute harbor-ui >/dev/null 2>&1; then
  kubectl -n harbor get httproute harbor-ui -o wide
  HOST="$(kubectl -n harbor get httproute harbor-ui -o jsonpath='{.spec.hostnames[0]}' 2>/dev/null || true)"
  [ -n "${HOST}" ] && echo "Harbor UI / registry: http://${HOST}/"
else
  echo "Harbor HTTPRoute is not present."
  echo "Reconcile from Windows with: .\\scripts\\publish.ps1 harbor"
fi
