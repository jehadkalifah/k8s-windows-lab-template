$ErrorActionPreference = "Stop"
# Intentionally kept as a lightweight trigger target. The main idempotent
# configuration is executed by up.ps1 after all nodes are online.
Write-Host "Cluster finalization hook completed."
