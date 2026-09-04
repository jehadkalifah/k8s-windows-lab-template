$ErrorActionPreference = "Stop"
$configFile = Join-Path $PSScriptRoot "lab-config.ps1"
if (-not (Test-Path $configFile)) {
    throw @"
Missing scripts\lab-config.ps1.

Create it first:
  Copy-Item .\scripts\lab-config.ps1.example .\scripts\lab-config.ps1

Then configure:
  K8S_BRIDGE_ADAPTER
  K3S_MASTER_LAN_IP
  K3S_WORKER1_LAN_IP
  K3S_WORKER2_LAN_IP
  K3S_API_LAN_IP
  K3S_FLANNEL_IFACE
  METALLB_POOL_START
  METALLB_POOL_END
"@
}
. $configFile

if ([string]::IsNullOrWhiteSpace($env:K8S_GATEWAY_NAMESPACE)) {
    $env:K8S_GATEWAY_NAMESPACE = "istio-ingress"
}
if ([string]::IsNullOrWhiteSpace($env:K8S_GATEWAY_NAME)) {
    $env:K8S_GATEWAY_NAME = "public-gateway"
}


if ([string]::IsNullOrWhiteSpace($env:VAGRANT_BOOT_TIMEOUT)) {
    $env:VAGRANT_BOOT_TIMEOUT = "600"
}

if ([string]::IsNullOrWhiteSpace($env:JENKINS_MGMT_IP)) {
    $env:JENKINS_MGMT_IP = "192.168.56.20"
}
if ([string]::IsNullOrWhiteSpace($env:JENKINS_LAN_IP)) {
    $env:JENKINS_LAN_IP = "192.168.100.220"
}
if ([string]::IsNullOrWhiteSpace($env:JENKINS_CPUS)) {
    $env:JENKINS_CPUS = "2"
}
if ([string]::IsNullOrWhiteSpace($env:JENKINS_MEM)) {
    $env:JENKINS_MEM = "4096"
}
if ([string]::IsNullOrWhiteSpace($env:JENKINS_VERSION)) {
    $env:JENKINS_VERSION = "2.568.3"
}

if ([string]::IsNullOrWhiteSpace($env:K3S_FLANNEL_IFACE)) {
    $env:K3S_FLANNEL_IFACE = "eth1"
}
$required = @(
    "K8S_BRIDGE_ADAPTER",
    "K3S_MASTER_LAN_IP",
    "K3S_WORKER1_LAN_IP",
    "K3S_WORKER2_LAN_IP",
    "K3S_API_LAN_IP",
    "METALLB_POOL_START",
    "METALLB_POOL_END"
)
foreach ($name in $required) {
    $value = [Environment]::GetEnvironmentVariable($name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Environment variable $name is missing in scripts\lab-config.ps1."
    }
}
$ipVars = $required | Where-Object { $_ -ne "K8S_BRIDGE_ADAPTER" }
foreach ($name in $ipVars) {
    $value = [Environment]::GetEnvironmentVariable($name)
    $parsed = $null
    if (-not [System.Net.IPAddress]::TryParse($value, [ref]$parsed)) {
        throw "$name='$value' is not a valid IP address."
    }
}
if ($env:K3S_API_LAN_IP -ne $env:K3S_MASTER_LAN_IP) {
    Write-Host "WARNING: K3S_API_LAN_IP differs from K3S_MASTER_LAN_IP." -ForegroundColor Yellow
}


$jenkinsIpVars = @("JENKINS_MGMT_IP","JENKINS_LAN_IP")
foreach ($name in $jenkinsIpVars) {
    $value = [Environment]::GetEnvironmentVariable($name)
    $parsed = $null
    if (-not [System.Net.IPAddress]::TryParse($value, [ref]$parsed)) {
        throw "$name='$value' is not a valid IP address."
    }
}
