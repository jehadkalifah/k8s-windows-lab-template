$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $RepoRoot
try {
    Write-Host "=== MetalLB pods ===" -ForegroundColor Cyan
    vagrant ssh k3s-master -c "sudo kubectl -n metallb-system get pods -o wide"

    Write-Host ""
    Write-Host "=== Webhook Service / Endpoints ===" -ForegroundColor Cyan
    vagrant ssh k3s-master -c "sudo kubectl -n metallb-system get svc metallb-webhook-service -o wide"
    vagrant ssh k3s-master -c "sudo kubectl -n metallb-system get endpoints metallb-webhook-service -o wide"

    Write-Host ""
    Write-Host "=== ValidatingWebhookConfiguration ===" -ForegroundColor Cyan
    vagrant ssh k3s-master -c "sudo kubectl get validatingwebhookconfiguration metallb-webhook-configuration"

    Write-Host ""
    Write-Host "=== Reachability from k3s-master ===" -ForegroundColor Cyan
    $cmd = @'
WEBHOOK_IP=$(sudo kubectl -n metallb-system get svc metallb-webhook-service -o jsonpath='{.spec.clusterIP}');
echo "Webhook ClusterIP: ${WEBHOOK_IP}";
curl -kvsS --max-time 8 "https://${WEBHOOK_IP}/validate-metallb-io-v1beta1-ipaddresspool?timeout=10s" 2>&1 | tail -30
'@
    vagrant ssh k3s-master -c $cmd
}
finally {
    Pop-Location
}
