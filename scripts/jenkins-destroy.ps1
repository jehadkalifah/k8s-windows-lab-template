$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $RepoRoot
try {
    Write-Host "Removing Jenkins Kubernetes publishing bridge if the cluster is running..." -ForegroundColor Yellow
    $masterRunning = (vagrant status k3s-master --machine-readable | Select-String ",state,running") -ne $null
    if ($masterRunning) {
        vagrant ssh k3s-master -c "sudo kubectl delete namespace jenkins --ignore-not-found=true"
    }

    Write-Host ""
    Write-Host "Destroying Jenkins VM. This deletes Jenkins data stored inside that VM." -ForegroundColor Red
    vagrant destroy -f jenkins
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to destroy Jenkins VM."
    }
}
finally {
    Pop-Location
}
