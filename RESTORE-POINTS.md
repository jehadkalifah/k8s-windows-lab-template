# Restore Points

This project supports multiple named restore points at two levels.

## VM-level restore points

VM restore points use Vagrant/VirtualBox snapshots and capture the state of all three VMs.

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

## Cluster-level restore points

Cluster restore points use Velero.

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

## Combined helper

Create both types with the same logical name:

```powershell
.\scripts\restore-point.ps1 create before-upgrade -Level both
```

List all restore points:

```powershell
.\scripts\restore-point.ps1 list
```

Restore the full VM/lab snapshot:

```powershell
.\scripts\restore-point.ps1 restore before-upgrade -Level vm
```

Restore Kubernetes resources and backed-up PV data:

```powershell
.\scripts\restore-point.ps1 restore before-upgrade -Level cluster
```

Delete both:

```powershell
.\scripts\restore-point.ps1 delete before-upgrade -Level both
```

Restoring with `-Level both` is intentionally not allowed. VM rollback and Velero restore are separate recovery strategies; select the one appropriate to the failure.
