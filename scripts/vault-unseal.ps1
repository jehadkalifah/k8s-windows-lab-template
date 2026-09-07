$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $RepoRoot

try {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host " Vault Unseal" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    $SecureKey = Read-Host "Enter Vault unseal key" -AsSecureString
    $Ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureKey)

    try {
        $UnsealKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($Ptr)

        if ([string]::IsNullOrWhiteSpace($UnsealKey)) {
            throw "Unseal key cannot be empty."
        }

        Write-Host ""
        Write-Host "Discovering Vault server pods..." -ForegroundColor Cyan

        $PodOutput = @(
            vagrant ssh k3s-master -c `
            "sudo kubectl -n vault get pods -l app.kubernetes.io/name=vault,component=server -o name"
        )

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to discover Vault pods."
        }

        $Pods = @(
            $PodOutput |
            ForEach-Object {
                $_.Trim() -replace '^pod/', ''
            } |
            Where-Object {
                $_ -match '^vault-\d+$'
            }
        )

        if ($Pods.Count -eq 0) {
            throw "No Vault server pods found."
        }

        Write-Host "Found Vault pods:" -ForegroundColor Green

        foreach ($Pod in $Pods) {
            Write-Host "  $Pod"
        }

        foreach ($Pod in $Pods) {

            Write-Host ""
            Write-Host "Checking $Pod..." -ForegroundColor Cyan

            $Status = @(
                vagrant ssh k3s-master -c `
                "sudo kubectl -n vault exec $Pod -- sh -c 'VAULT_ADDR=http://127.0.0.1:8200 vault status -format=json 2>/dev/null || true'"
            ) -join "`n"

            if ($Status -match '"initialized"\s*:\s*false') {
                Write-Host "$Pod is not initialized. Skipping." -ForegroundColor Yellow
                continue
            }

            if ($Status -match '"sealed"\s*:\s*false') {
                Write-Host "$Pod is already unsealed." -ForegroundColor Green
                continue
            }

            Write-Host "Unsealing $Pod..." -ForegroundColor Yellow

            vagrant ssh k3s-master -c `
            "sudo kubectl -n vault exec $Pod -- sh -c 'VAULT_ADDR=http://127.0.0.1:8200 vault operator unseal ""$UnsealKey"" >/dev/null'"

            if ($LASTEXITCODE -ne 0) {
                throw "Failed to unseal $Pod."
            }

            Write-Host "$Pod unsealed." -ForegroundColor Green
        }

        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host " Final Vault Status" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan

        foreach ($Pod in $Pods) {

            Write-Host ""
            Write-Host "--- $Pod ---"

            vagrant ssh k3s-master -c `
            "sudo kubectl -n vault exec $Pod -- sh -c 'VAULT_ADDR=http://127.0.0.1:8200 vault status || true'"
        }

        Write-Host ""
        Write-Host "Vault unseal completed." -ForegroundColor Green
    }
    finally {

        if ($Ptr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Ptr)
        }

        $UnsealKey = $null
        $SecureKey = $null
    }
}
finally {
    Pop-Location
}