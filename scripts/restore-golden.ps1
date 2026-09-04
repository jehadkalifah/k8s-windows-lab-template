param(
    [ValidateSet("vm","cluster")]
    [string]$Level = "vm"
)

$ErrorActionPreference = "Stop"
& "$PSScriptRoot\restore-point.ps1" restore "golden-clean" -Level $Level
