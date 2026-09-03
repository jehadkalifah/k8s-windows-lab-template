# Longhorn — Stage 2 Component

Pinned version:

```text
1.12.1
```

Install:

```powershell
.\scripts\deploy.ps1 longhorn
```

Status:

```powershell
.\scripts\deployment-status.ps1 longhorn
```

The default `longhorn` StorageClass uses two replicas for this three-node lab.

UI:

```powershell
kubectl -n longhorn-system port-forward svc/longhorn-frontend 8081:80
```

Open `http://127.0.0.1:8081`.
