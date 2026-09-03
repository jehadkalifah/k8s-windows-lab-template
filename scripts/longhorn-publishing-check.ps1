$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
. "$PSScriptRoot\load-config.ps1"

Push-Location $RepoRoot
try {
    Write-Host "=== Longhorn publishing check ===" -ForegroundColor Cyan

    $cmd = @'
sudo bash -lc '
set -e
IP="$(kubectl -n istio-ingress get gateway public-gateway -o jsonpath="{.status.addresses[0].value}")"
HOST="$(kubectl -n longhorn-system get httproute longhorn-ui -o jsonpath="{.spec.hostnames[0]}" 2>/dev/null || true)"

echo "Gateway IP:    ${IP}"
echo "Longhorn host: ${HOST:-<empty>}"
echo

kubectl -n longhorn-system get httproute longhorn-entry longhorn-ui -o wide || true

if [ -z "${HOST}" ]; then
  echo
  echo "ERROR: longhorn-ui.spec.hostnames[0] is empty."
  exit 2
fi

echo
echo "Longhorn URL: http://${HOST}/"
'
'@

    vagrant ssh k3s-master -c $cmd
    if ($LASTEXITCODE -ne 0) {
        throw "Longhorn publishing validation failed."
    }
}
finally {
    Pop-Location
}
