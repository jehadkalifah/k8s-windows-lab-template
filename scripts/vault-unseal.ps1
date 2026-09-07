$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $RepoRoot
try {
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host " HASHICORP VAULT - UNSEAL" -ForegroundColor Cyan
    Write-Host "====================================================" -ForegroundColor Cyan

    $secureKey = Read-Host "Enter the Vault unseal key" -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)

    try {
        $unsealKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)

        if ([string]::IsNullOrWhiteSpace($unsealKey)) {
            throw "Unseal key cannot be empty."
        }

        foreach ($Pod in @("vault-0","vault-1","vault-2")) {
            Write-Host "Unsealing $Pod..." -ForegroundColor Cyan
            & vagrant ssh k3s-master -c "sudo kubectl -n vault exec $Pod -- sh -c 'VAULT_ADDR=http://127.0.0.1:8200 vault operator unseal ""$unsealKey"" >/dev/null'"
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to unseal $Pod."
            }
        }

        Write-Host ""
        Write-Host "Vault status:" -ForegroundColor Cyan
        & vagrant ssh k3s-master -c "sudo bash /vagrant/deployments/vault/status.sh"

        if ($LASTEXITCODE -ne 0) {
            throw "Could not read Vault status."
        }

        Write-Host ""
        Write-Host "Vault unseal completed." -ForegroundColor Green
    }
    finally {
        if ($ptr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
        }
        $unsealKey = $null
        $secureKey = $null
    }
}
finally {
    Pop-Location
}
