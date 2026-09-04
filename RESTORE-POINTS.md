# Restore Points

This project supports named restore points at two independent levels:

1. **VM snapshots** for the three K3s nodes.
2. **Velero backups** for Kubernetes resources and backed-up persistent data.

Jenkins is an external VM and is intentionally excluded from all K3s restore
points and Velero backups.

## Exact behavior of `-Level both`

```powershell
.\scripts\restore-point.ps1 create app-v1 -Level both
```

The workflow is:

```text
1. Gracefully halt all lab VMs, including Jenkins if it is running.
2. Snapshot ONLY:
     k3s-master
     k3s-worker1
     k3s-worker2
3. Do NOT snapshot Jenkins.
4. Start ONLY:
     k3s-master
     k3s-worker1
     k3s-worker2
5. Leave Jenkins stopped.
6. Wait for SSH and all 3 Kubernetes nodes to become Ready.
7. Verify Velero is Ready.
8. Create the Velero backup with the same logical name.
```

The scripts use a 600-second Vagrant boot timeout and additionally verify the
actual VirtualBox/Vagrant state plus SSH. A Vagrant boot-timeout exit does not
cause a false failure if the VM is actually running and SSH becomes reachable.

## VM-level restore points

Create:

```powershell
.\scripts\vm-points.ps1 create before-upgrade
```

List:

```powershell
.\scripts\vm-points.ps1 list
```

Restore:

```powershell
.\scripts\vm-points.ps1 restore before-upgrade
```

Delete:

```powershell
.\scripts\vm-points.ps1 delete before-upgrade
```

VM create/restore stops Jenkins if it is running, snapshots/restores only the
three K3s nodes, restarts only the K3s nodes, waits for Kubernetes, and leaves
Jenkins stopped.

## Cluster-level / Velero restore points

Create:

```powershell
.\scripts\cluster-points.ps1 create before-upgrade
```

List:

```powershell
.\scripts\cluster-points.ps1 list
```

Describe:

```powershell
.\scripts\cluster-points.ps1 describe before-upgrade
```

Restore:

```powershell
.\scripts\cluster-points.ps1 restore before-upgrade
```

Delete:

```powershell
.\scripts\cluster-points.ps1 delete before-upgrade
```

Every Velero operation ensures only the three K3s VMs are running and Ready.
It never starts Jenkins.

## Combined helper

Create both types:

```powershell
.\scripts\restore-point.ps1 create before-upgrade -Level both
```

List all:

```powershell
.\scripts\restore-point.ps1 list
```

Restore the full VM/K3s state:

```powershell
.\scripts\restore-point.ps1 restore before-upgrade -Level vm
```

Restore Kubernetes resources/PV backups into the current healthy cluster:

```powershell
.\scripts\restore-point.ps1 restore before-upgrade -Level cluster
```

Delete both:

```powershell
.\scripts\restore-point.ps1 delete before-upgrade -Level both
```

`restore -Level both` is intentionally prohibited because a VirtualBox snapshot
rollback and a Velero restore are different recovery mechanisms. Choose one.

## Golden clean

Create both the VM and Velero `golden-clean` restore points:

```powershell
.\scripts\create-golden.ps1
```

Equivalent:

```powershell
.\scripts\restore-point.ps1 create golden-clean -Level both
```

Restore VM state:

```powershell
.\scripts\restore-golden.ps1 -Level vm
```

Restore Kubernetes state with Velero:

```powershell
.\scripts\restore-golden.ps1 -Level cluster
```

## Standalone Velero helpers

Backup:

```powershell
.\scripts\backup.ps1 -Name before-change
```

Restore:

```powershell
.\scripts\restore-velero.ps1 -Name before-change
```

Both helpers start/check only the three K3s nodes. Jenkins is never started.
