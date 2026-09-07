# Stakater Reloader — Stage 2 Component

Pinned versions:

```text
Reloader Helm chart: 2.2.16
Reloader app:        v1.4.21
```

Install:

```powershell
.\scripts\deploy.ps1 reloader
```

Status:

```powershell
.\scripts\deployment-status.ps1 reloader
```

Remove:

```powershell
.\scripts\remove-deployment.ps1 reloader
```

Reloader has no UI, no HTTPRoute, and no PVC.

The lab uses:

```yaml
reloader:
  watchGlobally: true
  autoReloadAll: false
  reloadStrategy: annotations
  ignoreJobs: true
  ignoreCronJobs: true
```

Applications opt in explicitly:

```yaml
metadata:
  annotations:
    reloader.stakater.com/auto: "true"
```

Then a referenced Secret or ConfigMap update causes Reloader to trigger a
rolling update of that workload.

See:

```text
deployments/reloader/examples/workload.yaml
```

The example is documentation/testing material only and is not installed by
`deploy.ps1`.
