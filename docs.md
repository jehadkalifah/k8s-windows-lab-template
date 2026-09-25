# Operational runbook

## Full lifecycle

```powershell
.\scripts\up.ps1
.\scripts\create-golden.ps1
.\scripts\backup.ps1
.\scripts\restore-golden.ps1
.\scripts\destroy.ps1
```

## Kubernetes context

```powershell
.\scripts\get-kubeconfig.ps1
.\scripts\use-kubeconfig.ps1
kubectl get nodes
```

## Golden snapshot

The golden snapshot is VM-level. It is the preferred reset mechanism for local lab work.

Velero is the logical Kubernetes backup mechanism.


## LAN bridge configuration

```powershell
.\scripts\show-bridges.ps1
Copy-Item .\scripts\lab-config.ps1.example .\scripts\lab-config.ps1
notepad .\scripts\lab-config.ps1
.\scripts\up.ps1
```

The host-only addresses remain stable for cluster management. MetalLB service
addresses are allocated from the configured physical-LAN pool.

## VM root disk sizing

The Vagrant lab now grows each Ubuntu root disk to **250GB by default**
(`256000` MB) for `k3s-master`, `k3s-worker1`, `k3s-worker2`, and `jenkins`.

Optional overrides:

```powershell
$env:K8S_MASTER_DISK_MB = "256000"
$env:K8S_WORKER_DISK_MB = "256000"
$env:JENKINS_DISK_MB    = "256000"
```

Install the required Vagrant plugin once before `vagrant up`:

```powershell
vagrant plugin install vagrant-disksize
```

The guest bootstrap scripts automatically run `growpart` plus the appropriate
filesystem grow command during provisioning, so no manual `resize2fs` or
`xfs_growfs` step is required.
