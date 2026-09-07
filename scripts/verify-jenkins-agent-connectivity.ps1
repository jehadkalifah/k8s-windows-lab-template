param(
    [string]$JenkinsUrl = "http://192.168.100.220:8080/jenkins/"
)

$ErrorActionPreference = "Stop"
$Pod = "jenkins-connect-test"

kubectl -n jenkins-agents delete pod $Pod --ignore-not-found=true | Out-Null
kubectl -n jenkins-agents run $Pod `
  --image=curlimages/curl:8.16.0 `
  --restart=Never `
  --command -- sh -c "curl -fsS -o /dev/null -w '%{http_code}' '$JenkinsUrl/login'"
if ($LASTEXITCODE -ne 0) { throw "Could not create connectivity test pod." }

try {
    kubectl -n jenkins-agents wait --for=jsonpath='{.status.phase}'=Succeeded pod/$Pod --timeout=90s | Out-Null
    $Code = (kubectl -n jenkins-agents logs $Pod).Trim()
    Write-Host "Jenkins HTTP status: $Code" -ForegroundColor Green
    if ($Code -notmatch '^(200|301|302|403)$') { throw "Unexpected Jenkins status $Code" }
}
finally {
    kubectl -n jenkins-agents delete pod $Pod --ignore-not-found=true | Out-Null
}
