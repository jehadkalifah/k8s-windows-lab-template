$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot

function Invoke-VagrantCommand {
    param([Parameter(Mandatory=$true)][string]$Command)

    $output = & vagrant ssh k3s-master -c $Command
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed: $Command"
    }
    return $output
}

Push-Location $RepoRoot
try {
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host " HASHICORP VAULT - INITIALIZE HA RAFT" -ForegroundColor Cyan
    Write-Host "====================================================" -ForegroundColor Cyan

    $statusRaw = (& vagrant ssh k3s-master -c "sudo kubectl -n vault exec vault-0 -- sh -c 'VAULT_ADDR=http://127.0.0.1:8200 vault status -format=json 2>/dev/null || true'") -join "`n"

    if ($statusRaw -match '"initialized"\s*:\s*true') {
        Write-Host ""
        Write-Host "Vault is already initialized." -ForegroundColor Yellow
        Write-Host "Use this after a restart if it is sealed:"
        Write-Host "  .\scripts\vault-unseal.ps1"
        exit 0
    }

    Write-Host ""
    Write-Host "Initializing vault-0 with one Shamir key/share for this local lab..." -ForegroundColor Cyan

    $raw = (& vagrant ssh k3s-master -c "sudo kubectl -n vault exec vault-0 -- sh -c 'VAULT_ADDR=http://127.0.0.1:8200 vault operator init -key-shares=1 -key-threshold=1 -format=json'") -join "`n"
    if ($LASTEXITCODE -ne 0) {
        throw "Vault initialization failed."
    }

    $start = $raw.IndexOf("{")
    $end = $raw.LastIndexOf("}")
    if ($start -lt 0 -or $end -lt $start) {
        throw "Could not parse Vault initialization output."
    }

    $init = $raw.Substring($start, $end - $start + 1) | ConvertFrom-Json
    $unsealKey = [string]$init.unseal_keys_b64[0]
    $rootToken = [string]$init.root_token

    if ([string]::IsNullOrWhiteSpace($unsealKey) -or [string]::IsNullOrWhiteSpace($rootToken)) {
        throw "Vault did not return the expected unseal key/root token."
    }

    Write-Host ""
    Write-Host "Unsealing vault-0..." -ForegroundColor Cyan
    Invoke-VagrantCommand "sudo kubectl -n vault exec vault-0 -- sh -c 'VAULT_ADDR=http://127.0.0.1:8200 vault operator unseal ""$unsealKey"" >/dev/null'"

    foreach ($Pod in @("vault-1","vault-2")) {
        Write-Host "Joining $Pod to the Raft cluster..." -ForegroundColor Cyan
        Invoke-VagrantCommand "sudo kubectl -n vault exec $Pod -- sh -c 'VAULT_ADDR=http://127.0.0.1:8200 vault operator raft join http://vault-0.vault-internal:8200'"
        Write-Host "Unsealing $Pod..." -ForegroundColor Cyan
        Invoke-VagrantCommand "sudo kubectl -n vault exec $Pod -- sh -c 'VAULT_ADDR=http://127.0.0.1:8200 vault operator unseal ""$unsealKey"" >/dev/null'"
    }

    Write-Host ""
    Write-Host "Waiting for Vault services..." -ForegroundColor Cyan
    Start-Sleep -Seconds 3

    Write-Host ""
    Write-Host "Raft peers:" -ForegroundColor Cyan
    Invoke-VagrantCommand "sudo kubectl -n vault exec vault-0 -- sh -c 'VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=""$rootToken"" vault operator raft list-peers'"

    Write-Host ""
    Write-Host "====================================================" -ForegroundColor Yellow
    Write-Host " SAVE THESE VALUES SECURELY - THEY ARE SHOWN ONCE" -ForegroundColor Yellow
    Write-Host "====================================================" -ForegroundColor Yellow
    Write-Host "Unseal Key: $unsealKey"
    Write-Host "Root Token: $rootToken"
    Write-Host ""
    Write-Host "DO NOT commit either value to Git or store them in the repo." -ForegroundColor Red
    Write-Host ""
    Write-Host "Vault HA Raft initialization completed." -ForegroundColor Green
    Write-Host "Status:"
    Write-Host "  .\scripts\deployment-status.ps1 vault"
    Write-Host "Publishing:"
    Write-Host "  .\scripts\publish.ps1 vault"
}
finally {
    Pop-Location
}
