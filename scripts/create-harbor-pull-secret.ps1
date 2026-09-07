param(
    [string]$Namespace = "demo",
    [string]$SecretName = "harbor-registry",
    [string]$Registry = "harbor.192-168-100-240.nip.io"
)
$ErrorActionPreference = "Stop"

kubectl get namespace $Namespace | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Namespace '$Namespace' does not exist." }

$Username = Read-Host "Harbor robot username"
$SecurePassword = Read-Host "Harbor robot secret/token" -AsSecureString
$Ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
try {
    $Password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($Ptr)
    kubectl -n $Namespace create secret docker-registry $SecretName --docker-server=$Registry --docker-username="$Username" --docker-password="$Password" --dry-run=client -o yaml | kubectl apply -f -
    if ($LASTEXITCODE -ne 0) { throw "Failed to create imagePullSecret." }
}
finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Ptr)
    $Password = $null
}

Write-Host "Created/updated $Namespace/$SecretName" -ForegroundColor Green
