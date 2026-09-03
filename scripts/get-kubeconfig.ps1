$ErrorActionPreference = "Stop"

New-Item -ItemType Directory -Force -Path ".kube" | Out-Null

vagrant ssh k3s-master -c "sudo cat /etc/rancher/k3s/k3s.yaml" | Out-File -Encoding ascii ".kube\lab-kubeconfig.yaml"

$content = Get-Content ".kube\lab-kubeconfig.yaml" -Raw
$content = $content -replace "https://127\.0\.0\.1:6443", "https://192.168.56.10:6443"
Set-Content -Path ".kube\lab-kubeconfig.yaml" -Value $content -NoNewline

Write-Host "Kubeconfig written to .kube\lab-kubeconfig.yaml" -ForegroundColor Green
