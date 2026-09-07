param(
    [string]$KubernetesServer = "https://192.168.100.210:6443",
    [string]$OutputFile = "jenkins-agent-manager.kubeconfig"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$RbacFile = Join-Path $RepoRoot "kubernetes\jenkins-agents\namespace-rbac.yaml"
$TokenFile = Join-Path $RepoRoot "kubernetes\jenkins-agents\lab-token-secret.yaml"
$OutputPath = Join-Path $RepoRoot $OutputFile

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Jenkins -> Kubernetes Access Bootstrap" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

kubectl config current-context
if ($LASTEXITCODE -ne 0) { throw "kubectl is not connected to the cluster." }

kubectl apply -f $RbacFile
if ($LASTEXITCODE -ne 0) { throw "Failed to apply Jenkins RBAC." }

kubectl apply -f $TokenFile
if ($LASTEXITCODE -ne 0) { throw "Failed to create ServiceAccount token Secret." }

$TokenB64 = $null
$CaB64 = $null
for ($i = 0; $i -lt 30; $i++) {
    $TokenB64 = kubectl -n jenkins-agents get secret jenkins-agent-manager-token -o jsonpath='{.data.token}' 2>$null
    $CaB64 = kubectl -n jenkins-agents get secret jenkins-agent-manager-token -o jsonpath='{.data.ca\.crt}' 2>$null
    if ($TokenB64 -and $CaB64) { break }
    Start-Sleep -Seconds 1
}

if (-not $TokenB64) { throw "Kubernetes did not populate the ServiceAccount token." }
if (-not $CaB64) { throw "Kubernetes did not populate the cluster CA." }

$Token = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($TokenB64))

$KubeConfig = @"
apiVersion: v1
kind: Config
clusters:
  - name: k3s-lab
    cluster:
      server: $KubernetesServer
      certificate-authority-data: $CaB64
contexts:
  - name: jenkins-agent-manager@k3s-lab
    context:
      cluster: k3s-lab
      namespace: jenkins-agents
      user: jenkins-agent-manager
current-context: jenkins-agent-manager@k3s-lab
users:
  - name: jenkins-agent-manager
    user:
      token: $Token
"@

[IO.File]::WriteAllText($OutputPath, $KubeConfig, (New-Object Text.UTF8Encoding($false)))
Write-Host "Created: $OutputPath" -ForegroundColor Green
Write-Host "The token was not printed to the console." -ForegroundColor Yellow

$CanAgent = (kubectl --kubeconfig=$OutputPath auth can-i create pods -n jenkins-agents).Trim()
$CanDefault = (kubectl --kubeconfig=$OutputPath auth can-i create pods -n default).Trim()
Write-Host "Create pods in jenkins-agents: $CanAgent"
Write-Host "Create pods in default:        $CanDefault"

if ($CanAgent -ne "yes") { throw "Jenkins kubeconfig cannot create agent pods." }
if ($CanDefault -ne "no") { throw "Jenkins kubeconfig is broader than intended." }

Write-Host "Upload the kubeconfig to Jenkins as a Secret file credential." -ForegroundColor Green
Write-Host "For production, replace the long-lived lab token with a short-lived or rotated authentication mechanism." -ForegroundColor Yellow
