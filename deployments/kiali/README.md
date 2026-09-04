# Kiali Operator + Kiali — Stage 2 Component

Pinned version:

```text
Kiali Operator: 2.31.0
Kiali Server:   2.31.0
```

The repository uses the Kiali Operator, Kiali's recommended installation model.

Dependencies:

```text
Monitoring / Prometheus
Istio
```

Install:

```powershell
.\scripts\deploy.ps1 kiali
```

Status:

```powershell
.\scripts\deployment-status.ps1 kiali
```

Publish:

```powershell
.\scripts\publish.ps1 kiali
```

Open:

```text
http://<gateway-ip>/kiali
```

Kiali does not require a PVC. It is stateless and reads Istio telemetry from Prometheus.
