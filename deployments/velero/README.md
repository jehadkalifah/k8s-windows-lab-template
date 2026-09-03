# Velero + MinIO — Stage 2 Component

Pinned:

```text
Velero chart: 12.1.0
Velero app:   1.18.1
AWS plugin:   v1.14.2
```

This lab stores Velero backups in MinIO on a Longhorn PVC.

Install:

```powershell
.\scripts\deploy.ps1 longhorn
.\scripts\deploy.ps1 velero
```

Create a backup:

```powershell
.\scripts\cluster-points.ps1 create before-change
```

MinIO:

```powershell
kubectl -n velero port-forward svc/minio 9001:9001
```

Login: `minio / minio123`.

Backups in this local MinIO do **not** survive a full VM/lab destroy.
