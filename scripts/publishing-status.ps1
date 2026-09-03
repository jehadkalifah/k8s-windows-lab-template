$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
. "$PSScriptRoot\load-config.ps1"

Push-Location $RepoRoot
try {
    $gatewayNamespace = if ($env:K8S_GATEWAY_NAMESPACE) { $env:K8S_GATEWAY_NAMESPACE } else { "istio-ingress" }
    $gatewayName = if ($env:K8S_GATEWAY_NAME) { $env:K8S_GATEWAY_NAME } else { "public-gateway" }

    $cmd = "sudo env GATEWAY_NAMESPACE='$gatewayNamespace' GATEWAY_NAME='$gatewayName' bash /vagrant/deployments/publishing/status.sh"
    vagrant ssh k3s-master -c $cmd

    if ($LASTEXITCODE -ne 0) {
        throw "Could not read publishing status."
    }
}
finally {
    Pop-Location
}
