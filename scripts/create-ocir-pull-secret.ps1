param(
    [string]$Namespace = "demo",
    [string]$Registry = "jed.ocir.io",
    [string]$SecretName = "ocir-pull-secret"
)

$ErrorActionPreference = "Stop"

$Username = Read-Host "OCIR username (<tenancy-namespace>/[domain/]<username>)"
$SecureToken = Read-Host "OCI auth token" -AsSecureString
$Ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureToken)

try {
    $Token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($Ptr)
    if ([string]::IsNullOrWhiteSpace($Username) -or [string]::IsNullOrWhiteSpace($Token)) {
        throw "Username and auth token are required."
    }

    kubectl get namespace $Namespace *> $null
    if ($LASTEXITCODE -ne 0) {
        kubectl create namespace $Namespace | Out-Null
    }

    $AuthRaw = "${Username}:${Token}"
    $AuthB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($AuthRaw))
    $DockerConfig = @{
        auths = @{
            $Registry = @{
                auth = $AuthB64
            }
        }
    } | ConvertTo-Json -Compress -Depth 5

    $DockerConfigB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($DockerConfig))
    $Manifest = @"
apiVersion: v1
kind: Secret
metadata:
  name: $SecretName
  namespace: $Namespace
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: $DockerConfigB64
"@

    $Manifest | kubectl apply -f -
    if ($LASTEXITCODE -ne 0) { throw "Failed to create OCIR pull Secret." }

    Write-Host "Created/updated $Namespace/$SecretName" -ForegroundColor Green
}
finally {
    if ($Ptr -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Ptr)
    }
    $Token = $null
    $SecureToken = $null
}
