$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
. "$PSScriptRoot\load-config.ps1"

$expected = @{
    "k3s-master"  = "192.168.56.10"
    "k3s-worker1" = "192.168.56.11"
    "k3s-worker2" = "192.168.56.12"
}

Push-Location $RepoRoot
try {
    Write-Host "=== Flannel VXLAN underlay ===" -ForegroundColor Cyan
    Write-Host "Expected interface: $env:K3S_FLANNEL_IFACE"
    Write-Host ""

    foreach ($node in @("k3s-master","k3s-worker1","k3s-worker2")) {
        $expectedIp = $expected[$node]
        Write-Host "$node -> expected $expectedIp on $env:K3S_FLANNEL_IFACE" -ForegroundColor Cyan

        $output = vagrant ssh $node -c "ip -d link show flannel.1"
        if ($LASTEXITCODE -ne 0) {
            throw "Could not inspect flannel.1 on $node."
        }

        $text = ($output -join "`n")
        if ($text -notmatch "local\s+$([regex]::Escape($expectedIp))\s+dev\s+$([regex]::Escape($env:K3S_FLANNEL_IFACE))") {
            Write-Host $text
            throw "Flannel on $node is NOT using $env:K3S_FLANNEL_IFACE/$expectedIp."
        }

        Write-Host "PASS" -ForegroundColor Green
        Write-Host ""
    }

    Write-Host "Flannel is correctly bound to the host-only Kubernetes network." -ForegroundColor Green
}
finally {
    Pop-Location
}
