$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$failures = @()

$required = @(
  "scripts\up.ps1",
  "scripts\deploy.ps1",
  "scripts\deployment-status.ps1",
  "scripts\remove-deployment.ps1",
  "scripts\check-flannel.ps1",
  "scripts\fix-flannel.ps1",
  "deployments\istio\install.sh",
  "deployments\istio\status.sh",
  "deployments\istio\remove.sh",
  "deployments\istio\manifests\gateway.yaml",
  "deployments\istio\manifests\demo.yaml",
  "deployments\cert-manager\install.sh",
  "deployments\cert-manager\status.sh",
  "deployments\cert-manager\remove.sh",
  "deployments\cert-manager\manifests\selfsigned-test.yaml"
)

foreach ($file in $required) {
    if (-not (Test-Path (Join-Path $RepoRoot $file))) {
        $failures += "Missing: $file"
    }
}

$up = Get-Content (Join-Path $RepoRoot "scripts\up.ps1") -Raw
if ($up -match "ansible-playbook") {
    $failures += "Stage 1 up.ps1 still invokes platform Ansible."
}

$gateway = Get-Content (Join-Path $RepoRoot "deployments\istio\manifests\gateway.yaml") -Raw
if ($gateway -notmatch "gatewayClassName:\s*istio") {
    $failures += "Istio Gateway does not use gatewayClassName: istio."
}

$install = Get-Content (Join-Path $RepoRoot "deployments\istio\install.sh") -Raw
if ($install -notmatch "blob\.istio\.io/istio-release/charts") {
    $failures += "Istio Helm repo is incorrect for 1.31."
}


$certManagerInstall = Get-Content (Join-Path $RepoRoot "deployments\cert-manager\install.sh") -Raw
if ($certManagerInstall -notmatch "oci://quay\.io/jetstack/charts/cert-manager") {
    $failures += "cert-manager OCI chart source is incorrect."
}
if ($certManagerInstall -notmatch "v1\.21\.1") {
    $failures += "cert-manager version pin v1.21.1 is missing."
}


$masterBootstrap = Get-Content (Join-Path $RepoRoot "ansible\bootstrap-master.sh") -Raw
$workerJoin = Get-Content (Join-Path $RepoRoot "ansible\join-worker.sh") -Raw
$vagrantfile = Get-Content (Join-Path $RepoRoot "Vagrantfile") -Raw

if ($masterBootstrap -notmatch 'flannel-iface:\s*"\$\{FLANNEL_IFACE\}"') {
    $failures += "Stage 1 bootstrap is missing flannel-iface on the K3s server."
}
if ($workerJoin -notmatch 'flannel-iface:\s*"\$\{FLANNEL_IFACE\}"') {
    $failures += "Stage 1 worker join is missing flannel-iface."
}
if ($vagrantfile -notmatch 'K3S_FLANNEL_IFACE') {
    $failures += "Vagrantfile is not passing K3S_FLANNEL_IFACE to K3s provisioning."
}


# Stage 2 extra module validation
$stage2Files = @(
    "deployments\longhorn\install.sh",
    "deployments\monitoring\install.sh",
    "deployments\argocd\install.sh",
    "deployments\velero\install.sh"
)
foreach ($file in $stage2Files) {
    if (-not (Test-Path (Join-Path $RepoRoot $file))) {
        $failures += "Missing Stage 2 module file: $file"
    }
}


# Shared Gateway publishing validation
$publishingFiles = @(
    "deployments\publishing\apply.sh",
    "deployments\publishing\status.sh",
    "deployments\publishing\routes\demo.yaml",
    "deployments\publishing\routes\longhorn.yaml",
    "deployments\publishing\routes\monitoring.yaml",
    "deployments\publishing\routes\argocd.yaml",
    "deployments\publishing\routes\minio.yaml",
    "scripts\publish.ps1",
    "scripts\publishing-status.ps1"
)
foreach ($file in $publishingFiles) {
    if (-not (Test-Path (Join-Path $RepoRoot $file))) {
        $failures += "Missing publishing file: $file"
    }
}


# HashiCorp Vault Stage 2 validation
$vaultFiles = @(
    "deployments\vault\values.yaml",
    "deployments\vault\install.sh",
    "deployments\vault\status.sh",
    "deployments\vault\remove.sh",
    "deployments\publishing\routes\vault.yaml",
    "scripts\vault-init.ps1",
    "scripts\vault-unseal.ps1"
)
foreach ($file in $vaultFiles) {
    if (-not (Test-Path (Join-Path $RepoRoot $file))) {
        $failures += "Missing Vault file: $file"
    }
}

# Kiali Operator Stage 2 validation
$kialiFiles = @(
    "deployments\kiali\kiali.yaml",
    "deployments\kiali\install.sh",
    "deployments\kiali\status.sh",
    "deployments\kiali\remove.sh",
    "deployments\publishing\routes\kiali.yaml"
)
foreach ($file in $kialiFiles) {
    if (-not (Test-Path (Join-Path $RepoRoot $file))) {
        $failures += "Missing Kiali file: $file"
    }
}


# Keycloak Operator Stage 2 validation
$keycloakFiles = @(
    "deployments\keycloak\keycloak.yaml",
    "deployments\keycloak\install.sh",
    "deployments\keycloak\status.sh",
    "deployments\keycloak\remove.sh",
    "deployments\keycloak\manifests\postgres.yaml",
    "deployments\publishing\routes\keycloak.yaml",
    "scripts\keycloak-admin.ps1"
)
foreach ($file in $keycloakFiles) {
    if (-not (Test-Path (Join-Path $RepoRoot $file))) {
        $failures += "Missing Keycloak file: $file"
    }
}


# Jenkins external VM validation
$jenkinsFiles = @(
    "ansible\bootstrap-jenkins.sh",
    "deployments\publishing\routes\jenkins.yaml",
    "external-services\jenkins\README.md",
    "scripts\jenkins-up.ps1",
    "scripts\jenkins-status.ps1",
    "scripts\jenkins-password.ps1",
    "scripts\jenkins-reprovision.ps1",
    "scripts\jenkins-destroy.ps1",
    ".gitattributes"
)
foreach ($file in $jenkinsFiles) {
    if (-not (Test-Path (Join-Path $RepoRoot $file))) {
        $failures += "Missing Jenkins file: $file"
    }
}


# Backup / restore / delete validation after external Jenkins VM integration
$restoreFiles = @(
    "scripts\restore-common.ps1",
    "scripts\restore-point.ps1",
    "scripts\vm-points.ps1",
    "scripts\cluster-points.ps1",
    "scripts\backup.ps1",
    "scripts\restore-velero.ps1",
    "scripts\create-golden.ps1",
    "scripts\restore-golden.ps1",
    "RESTORE-POINTS.md"
)
foreach ($file in $restoreFiles) {
    if (-not (Test-Path (Join-Path $RepoRoot $file))) {
        $failures += "Missing restore workflow file: $file"
    }
}

$restoreCommon = Get-Content (Join-Path $RepoRoot "scripts\restore-common.ps1") -Raw
$restorePoint = Get-Content (Join-Path $RepoRoot "scripts\restore-point.ps1") -Raw
$vmPoints = Get-Content (Join-Path $RepoRoot "scripts\vm-points.ps1") -Raw

if ($restoreCommon -notmatch '\$ClusterVMs\s*=\s*@\("k3s-master",\s*"k3s-worker1",\s*"k3s-worker2"\)') {
    $failures += "Restore workflow does not explicitly scope VM operations to the three K3s nodes."
}
if ($restoreCommon -notmatch '\$JenkinsVM\s*=\s*"jenkins"') {
    $failures += "Restore workflow does not explicitly track Jenkins exclusion."
}
if ($restoreCommon -notmatch 'Start-ClusterVMs') {
    $failures += "Restore workflow is missing cluster-only startup helper."
}
if ($vagrantfile -notmatch 'config\.vm\.boot_timeout.*600') {
    $failures += "Vagrant boot timeout correction is missing."
}
if ($restorePoint -match 'vagrant up --no-provision') {
    $failures += "restore-point.ps1 still contains generic vagrant up that can start Jenkins."
}
if ($vmPoints -notmatch 'Jenkins remains stopped by design') {
    $failures += "vm-points.ps1 does not document Jenkins remaining stopped."
}

if ($failures.Count -gt 0) {
    Write-Host "Repository validation FAILED" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
    exit 1
}

Write-Host "Repository validation passed." -ForegroundColor Green
Write-Host "Stage 1: K3s cluster only." -ForegroundColor Green
Write-Host "Stage 2: modular deployments; first component = istio." -ForegroundColor Green
