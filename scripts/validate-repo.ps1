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


# Jenkins dedicated lifecycle validation
$jenkinsLifecycleFiles = @(
    "scripts\jenkins-run.ps1",
    "scripts\jenkins-suspend.ps1",
    "scripts\jenkins-resume.ps1",
    "scripts\jenkins-shutdown.ps1"
)
foreach ($file in $jenkinsLifecycleFiles) {
    if (-not (Test-Path (Join-Path $RepoRoot $file))) {
        $failures += "Missing Jenkins lifecycle file: $file"
    }
}


# Stakater Reloader Stage 2 validation
$reloaderFiles = @(
    "deployments\reloader\values.yaml",
    "deployments\reloader\install.sh",
    "deployments\reloader\status.sh",
    "deployments\reloader\remove.sh",
    "deployments\reloader\README.md",
    "deployments\reloader\examples\workload.yaml"
)
foreach ($file in $reloaderFiles) {
    if (-not (Test-Path (Join-Path $RepoRoot $file))) {
        $failures += "Missing Reloader file: $file"
    }
}

$deployScript = Get-Content (Join-Path $RepoRoot "scripts\deploy.ps1") -Raw
$statusScript = Get-Content (Join-Path $RepoRoot "scripts\deployment-status.ps1") -Raw
$reloaderValues = Get-Content (Join-Path $RepoRoot "deployments\reloader\values.yaml") -Raw

if ($deployScript -notmatch '"argocd","reloader","istio"') {
    $failures += "Reloader is not in the expected Stage 2 order after Argo CD and before Istio."
}
if ($statusScript -notmatch '"argocd","reloader","istio"') {
    $failures += "Reloader is missing from the complete Stage 2 status order."
}
if ($reloaderValues -notmatch 'reloadStrategy:\s*annotations') {
    $failures += "Reloader is not configured with the annotations reload strategy."
}
if ($reloaderValues -notmatch 'autoReloadAll:\s*false') {
    $failures += "Reloader must use explicit workload opt-in."
}


# Harbor Stage 2 validation
$harborFiles = @(
    "deployments\harbor\values.yaml.tpl",
    "deployments\harbor\install.sh",
    "deployments\harbor\status.sh",
    "deployments\harbor\remove.sh",
    "deployments\harbor\admin.sh",
    "deployments\publishing\routes\harbor.yaml",
    "scripts\harbor-install.ps1",
    "scripts\harbor-status.ps1",
    "scripts\harbor-remove.ps1",
    "scripts\harbor-admin.ps1"
)
foreach ($file in $harborFiles) {
    if (-not (Test-Path (Join-Path $RepoRoot $file))) {
        $failures += "Missing Harbor file: $file"
    }
}

$harborWrapper = Get-Content (Join-Path $RepoRoot "scripts\harbor-install.ps1") -Raw
if ($harborWrapper -match 'Get-Command\s+(kubectl|helm)' -or
    $harborWrapper -match '(?m)^\s*(kubectl|helm)\s') {
    $failures += "Harbor Windows wrapper must not require local kubectl/helm."
}
if ($deployScript -notmatch '"keycloak","harbor","velero"') {
    $failures += "Harbor is not in the expected Stage 2 order."
}
if ($statusScript -notmatch '"keycloak","harbor","velero"') {
    $failures += "Harbor is missing from complete Stage 2 status."
}




# Harbor local-path storage validation
$harborValues = Join-Path $RepoRoot "deployments\harbor\values.yaml.tpl"
$harborInstall = Join-Path $RepoRoot "deployments\harbor\install.sh"
$harborRemove = Join-Path $RepoRoot "deployments\harbor\remove.sh"

if (Test-Path (Join-Path $RepoRoot "deployments\harbor\storageclass.yaml")) {
    $failures += "Obsolete Harbor longhorn-harbor StorageClass manifest still exists."
}

$harborValuesText = Get-Content $harborValues -Raw
if ($harborValuesText -match 'storageClass:\s*longhorn') {
    $failures += "Harbor values must not reference Longhorn."
}
if (($harborValuesText | Select-String -Pattern 'storageClass:\s*local-path' -AllMatches).Matches.Count -lt 5) {
    $failures += "All five Harbor PVC definitions must use local-path."
}

$harborInstallText = Get-Content $harborInstall -Raw
if ($harborInstallText -notmatch 'kubectl get storageclass local-path') {
    $failures += "Harbor installer does not verify local-path."
}
if ($harborInstallText -notmatch 'rancher\.io/local-path') {
    $failures += "Harbor installer does not verify the local-path provisioner."
}
if ($harborInstallText -match 'storageclass\.yaml') {
    $failures += "Harbor installer still references the obsolete custom StorageClass."
}
if ($harborInstallText -notmatch 'Existing Harbor PVCs use an incompatible StorageClass') {
    $failures += "Harbor installer does not protect against old incompatible PVCs."
}

$harborRemoveText = Get-Content $harborRemove -Raw
if ($harborRemoveText -match 'delete storageclass') {
    $failures += "Harbor removal must never delete the cluster local-path StorageClass."
}


# K3s packaged local-storage validation
$bootstrapMaster = Join-Path $RepoRoot "ansible\bootstrap-master.sh"
$localStorageEnsure = Join-Path $RepoRoot "deployments\k3s-local-storage\ensure.sh"
$localStorageStatus = Join-Path $RepoRoot "deployments\k3s-local-storage\status.sh"
$localStoragePs = Join-Path $RepoRoot "scripts\k3s-local-storage.ps1"

$bootstrapMasterText = Get-Content $bootstrapMaster -Raw

if ($bootstrapMasterText -match '(?m)^\s*-\s*local-storage\s*$') {
    $failures += "Stage 1 must not disable the K3s local-storage packaged component."
}

foreach ($file in @($localStorageEnsure, $localStorageStatus, $localStoragePs)) {
    if (-not (Test-Path $file)) {
        $failures += "Missing K3s local-storage helper: $file"
    }
}

if (Test-Path $localStorageEnsure) {
    $ensureText = Get-Content $localStorageEnsure -Raw

    if ($ensureText -notmatch 'config\.yaml\.before-local-storage-enable') {
        $failures += "K3s local-storage repair must back up config.yaml."
    }

    if ($ensureText -notmatch 'local-storage.*disable') {
        $failures += "K3s local-storage repair does not document/check the disabled packaged component."
    }

    if ($ensureText -notmatch 'systemctl restart k3s') {
        $failures += "K3s local-storage repair does not restart K3s after config correction."
    }

    if ($ensureText -notmatch 'rancher\.io/local-path') {
        $failures += "K3s local-storage repair does not verify the expected provisioner."
    }
}

$harborInstallFinal = Get-Content (Join-Path $RepoRoot "deployments\harbor\install.sh") -Raw
if ($harborInstallFinal -notmatch 'k3s-local-storage/ensure\.sh') {
    $failures += "Harbor installer must automatically ensure K3s local-storage."
}


# Harbor rendered StorageClass validation
$harborInstallRenderCheck = Get-Content (Join-Path $RepoRoot "deployments\harbor\install.sh") -Raw

if ($harborInstallRenderCheck -match "grep -c 'storageClassName: local-path'") {
    $failures += "Harbor installer still uses brittle unquoted-only StorageClass validation."
}

if ($harborInstallRenderCheck -notmatch 'RENDERED_LOCAL_PATH_COUNT') {
    $failures += "Harbor installer is missing rendered local-path validation."
}

if ($harborInstallRenderCheck -notmatch 'VALUES_LOCAL_PATH_COUNT') {
    $failures += "Harbor installer is missing values-level local-path validation."
}

if ($harborInstallRenderCheck -notmatch '\\"\?local-path\\"\?') {
    $failures += "Harbor rendered validation must accept quoted and unquoted local-path values."
}

if ($harborInstallRenderCheck -notmatch 'All rendered StorageClass lines') {
    $failures += "Harbor rendered validation should print StorageClass diagnostics on failure."
}

if ($failures.Count -gt 0) {
    Write-Host "Repository validation FAILED" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
    exit 1
}

Write-Host "Repository validation passed." -ForegroundColor Green
Write-Host "Stage 1: K3s cluster only." -ForegroundColor Green
Write-Host "Stage 2: modular deployments; first component = istio." -ForegroundColor Green
