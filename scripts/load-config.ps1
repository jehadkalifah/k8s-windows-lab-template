$ErrorActionPreference = "Stop"

$configFile = Join-Path $PSScriptRoot "lab-config.ps1"

if (-not (Test-Path $configFile)) {
    throw @"
Missing scripts\lab-config.ps1.

Create it first:

  Copy-Item .\scripts\lab-config.ps1.example .\scripts\lab-config.ps1

Then edit:
  K8S_BRIDGE_ADAPTER
  METALLB_POOL_START
  METALLB_POOL_END

Use:
  .\scripts\show-bridges.ps1

to list VirtualBox bridged adapters.
"@
}

. $configFile

$required = @(
    "K8S_BRIDGE_ADAPTER",
    "METALLB_POOL_START",
    "METALLB_POOL_END"
)

foreach ($name in $required) {
    $value = [Environment]::GetEnvironmentVariable($name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Environment variable $name is missing in scripts\lab-config.ps1."
    }
}
