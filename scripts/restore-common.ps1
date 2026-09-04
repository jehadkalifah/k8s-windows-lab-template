$ClusterVMs = @("k3s-master", "k3s-worker1", "k3s-worker2")
$JenkinsVM = "jenkins"

function Get-LabVMState {
    param([Parameter(Mandatory=$true)][string]$VM)

    $output = & vagrant status $VM --machine-readable 2>$null
    if ($LASTEXITCODE -ne 0) {
        return "unknown"
    }

    foreach ($line in $output) {
        if ($line -match ',state,([^,]+)$') {
            return $Matches[1]
        }
    }

    return "unknown"
}

function Stop-LabVMIfRunning {
    param([Parameter(Mandatory=$true)][string]$VM)

    $state = Get-LabVMState -VM $VM
    if ($state -in @("not_created", "unknown")) {
        Write-Host "$VM is not created/known; skipping halt." -ForegroundColor DarkGray
        return
    }

    if ($state -eq "poweroff" -or $state -eq "aborted") {
        Write-Host "$VM is already stopped ($state)." -ForegroundColor DarkGray
        return
    }

    Write-Host "Halting $VM..." -ForegroundColor Cyan
    & vagrant halt $VM
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to halt $VM."
    }
}

function Stop-AllLabVMsForRestorePoint {
    # Requested restore-point behavior:
    # 1. Stop the three K3s nodes.
    # 2. Stop Jenkins too if it exists/runs.
    # 3. Snapshot ONLY the K3s nodes.
    # 4. Restart ONLY the K3s nodes. Jenkins stays off.
    foreach ($vm in @($JenkinsVM) + $ClusterVMs) {
        Stop-LabVMIfRunning -VM $vm
    }
}

function Test-LabVMSSH {
    param([Parameter(Mandatory=$true)][string]$VM)

    & vagrant ssh $VM -c "true" *> $null
    return ($LASTEXITCODE -eq 0)
}

function Wait-LabVMSSH {
    param(
        [Parameter(Mandatory=$true)][string]$VM,
        [int]$TimeoutSeconds = 600
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $state = Get-LabVMState -VM $VM
        if ($state -eq "running" -and (Test-LabVMSSH -VM $VM)) {
            Write-Host "$VM is running and SSH is reachable." -ForegroundColor Green
            return
        }
        Start-Sleep -Seconds 5
    }

    throw "$VM did not become SSH-ready within $TimeoutSeconds seconds."
}

function Start-ClusterVM {
    param(
        [Parameter(Mandatory=$true)][string]$VM,
        [int]$TimeoutSeconds = 600
    )

    $state = Get-LabVMState -VM $VM
    if ($state -eq "running") {
        Write-Host "$VM is already running; verifying SSH..." -ForegroundColor DarkGray
        Wait-LabVMSSH -VM $VM -TimeoutSeconds $TimeoutSeconds
        return
    }

    Write-Host "Starting $VM without provisioning..." -ForegroundColor Cyan
    & vagrant up $VM --no-provision
    $upExit = $LASTEXITCODE

    if ($upExit -ne 0) {
        # Vagrant can return a boot-timeout error even though VirtualBox has
        # already booted the guest. Do not fail until state + SSH are checked.
        Write-Host "WARNING: 'vagrant up $VM' returned exit code $upExit. Verifying actual VM/SSH state before failing..." -ForegroundColor Yellow
    }

    Wait-LabVMSSH -VM $VM -TimeoutSeconds $TimeoutSeconds
}

function Start-ClusterVMs {
    param(
        [switch]$WaitForKubernetes,
        [int]$TimeoutSeconds = 600
    )

    # Vagrantfile requires bridge configuration for 'up'.
    . "$PSScriptRoot\load-config.ps1"

    foreach ($vm in $ClusterVMs) {
        Start-ClusterVM -VM $vm -TimeoutSeconds $TimeoutSeconds
    }

    if ($WaitForKubernetes) {
        Wait-KubernetesReady -TimeoutSeconds $TimeoutSeconds
    }
}

function Wait-KubernetesReady {
    param([int]$TimeoutSeconds = 600)

    Write-Host "Waiting for all three Kubernetes nodes to become Ready..." -ForegroundColor Cyan
    & vagrant ssh k3s-master -c "sudo kubectl wait --for=condition=Ready nodes --all --timeout=${TimeoutSeconds}s"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Current node status:" -ForegroundColor Yellow
        & vagrant ssh k3s-master -c "sudo kubectl get nodes -o wide" 2>$null
        throw "Kubernetes nodes did not become Ready within $TimeoutSeconds seconds."
    }

    $countOutput = & vagrant ssh k3s-master -c "sudo kubectl get nodes --no-headers | wc -l"
    if ($LASTEXITCODE -ne 0) {
        throw "Could not query Kubernetes node count."
    }

    $count = (($countOutput | Select-Object -Last 1) -as [string]).Trim()
    if ($count -ne "3") {
        throw "Expected exactly 3 Kubernetes nodes, found '$count'."
    }

    Write-Host "Kubernetes cluster is Ready (3/3 nodes)." -ForegroundColor Green
}

function Ensure-ClusterReady {
    param([int]$TimeoutSeconds = 600)

    Start-ClusterVMs -WaitForKubernetes -TimeoutSeconds $TimeoutSeconds
}

function Assert-VeleroReady {
    Write-Host "Checking Velero..." -ForegroundColor Cyan
    & vagrant ssh k3s-master -c "sudo kubectl -n velero rollout status deployment/velero --timeout=300s"
    if ($LASTEXITCODE -ne 0) {
        throw "Velero deployment is not Ready."
    }

    & vagrant ssh k3s-master -c "velero version --client-only >/dev/null"
    if ($LASTEXITCODE -ne 0) {
        throw "Velero CLI is not available on k3s-master."
    }

    $bslOutput = & vagrant ssh k3s-master -c "sudo kubectl -n velero get backupstoragelocation default -o jsonpath='{.status.phase}'" 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Could not read Velero BackupStorageLocation 'default'."
    }
    $bslPhase = (($bslOutput | Select-Object -Last 1) -as [string]).Trim()
    if ($bslPhase -ne "Available") {
        throw "Velero BackupStorageLocation 'default' is '$bslPhase', expected 'Available'."
    }

    Write-Host "Velero and BackupStorageLocation are Ready." -ForegroundColor Green
}
