param(
    [Parameter(Position=0)]
    [ValidateSet("all","argocd","demo","istio","kiali","longhorn","minio","monitoring","vault","velero")]
    [string]$Component = "all"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
. "$PSScriptRoot\load-config.ps1"

Push-Location $RepoRoot
try {
    $gatewayNamespace = if ($env:K8S_GATEWAY_NAMESPACE) { $env:K8S_GATEWAY_NAMESPACE } else { "istio-ingress" }
    $gatewayName = if ($env:K8S_GATEWAY_NAME) { $env:K8S_GATEWAY_NAME } else { "public-gateway" }

    $longhornHost = if ($env:LONGHORN_PUBLISH_HOST) { $env:LONGHORN_PUBLISH_HOST } else { "" }
    $vaultHost = if ($env:VAULT_PUBLISH_HOST) { $env:VAULT_PUBLISH_HOST } else { "" }
    $cmd = "sudo env GATEWAY_NAMESPACE='$gatewayNamespace' GATEWAY_NAME='$gatewayName' LONGHORN_PUBLISH_HOST='$longhornHost' VAULT_PUBLISH_HOST='$vaultHost' bash /vagrant/deployments/publishing/apply.sh '$Component'"
    vagrant ssh k3s-master -c $cmd

    if ($LASTEXITCODE -ne 0) {
        throw "Publishing reconciliation failed."
    }
}
finally {
    Pop-Location
}
