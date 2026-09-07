# Stage 2 Deployments

Stage 1 creates the K3s cluster only.

Stage 2 owns everything deployed on top of Kubernetes.

Current component:

```text
istio
```

Commands:

```powershell
.\scripts\deploy.ps1 istio
.\scripts\deployment-status.ps1 istio
.\scripts\remove-deployment.ps1 istio
```

Future components can be added as independent folders:

```text
deployments/
├── istio/
├── longhorn/
├── velero/
├── monitoring/
├── argocd/
└── applications/
```

## cert-manager

Install:

```powershell
.\scripts\deploy.ps1 cert-manager
```

Status:

```powershell
.\scripts\deployment-status.ps1 cert-manager
```

Remove:

```powershell
.\scripts\remove-deployment.ps1 cert-manager
```

cert-manager is installed independently so it can later provide automated TLS
certificates for Istio Gateway API and other Kubernetes workloads.
## Additional Stage 2 Modules

Complete Stage 2 set:

```text
cert-manager
longhorn
vault
monitoring
argocd
reloader
istio
kiali
keycloak
harbor
velero
```

Install all in dependency-safe order:

```powershell
.\scripts\deploy.ps1 all
```

Status:

```powershell
.\scripts\deployment-status.ps1 all
```

Pinned versions:

```text
cert-manager:          v1.21.1
Longhorn:              1.12.1
kube-prometheus-stack: 88.5.4
Argo CD chart:         10.4.0
Stakater Reloader:    chart 2.2.16 / app v1.4.21
Istio:                 1.31.0
MetalLB:               0.16.1
Velero chart:          12.1.0
Velero AWS plugin:     v1.14.2
```


## Shared Gateway Publishing

All browser-facing services are attached to:

```text
istio-ingress/public-gateway
```

through Kubernetes Gateway API `HTTPRoute` resources.

```powershell
.\scripts\publish.ps1 all
.\scripts\publishing-status.ps1
```

See `deployments/publishing/README.md` for the path map.


## HashiCorp Vault

Vault is installed after Longhorn because its Raft data uses the `longhorn`
StorageClass.

```powershell
.\scripts\deploy.ps1 vault
.\scripts\vault-init.ps1
.\scripts\deployment-status.ps1 vault
```

Pinned versions:

```text
Vault Helm chart: 0.34.1
Vault app:        2.0.4
```


## Kiali Operator

Kiali is installed after Monitoring and Istio because it consumes Istio telemetry from Prometheus.

```powershell
.\scripts\deploy.ps1 kiali
.\scripts\deployment-status.ps1 kiali
.\scripts\publish.ps1 kiali
```

Pinned version: `2.31.0`. Kiali does not need a PVC.


## Keycloak Operator + PostgreSQL

Keycloak is installed after Istio/Kiali in the complete lab order. Its
PostgreSQL database uses Longhorn persistent storage.

```powershell
.\scripts\deploy.ps1 keycloak
.\scripts\keycloak-admin.ps1
.\scripts\deployment-status.ps1 keycloak
.\scripts\publish.ps1 keycloak
```

Pinned:

```text
Keycloak / Operator: 26.7.3
PostgreSQL:          18
```

Database PVC:

```text
data-keycloak-postgres-0
10Gi
StorageClass: longhorn
```


## Stakater Reloader

Reloader is installed after Argo CD and before Istio in the complete Stage 2
order.

```powershell
.\scripts\deploy.ps1 reloader
.\scripts\deployment-status.ps1 reloader
.\scripts\remove-deployment.ps1 reloader
```

Pinned:

```text
Reloader chart: 2.2.16
Reloader app:   v1.4.21
```

Reloader has no UI and no PVC. Workloads must opt in explicitly with:

```yaml
metadata:
  annotations:
    reloader.stakater.com/auto: "true"
```


## Harbor Private Registry

Harbor follows the same Stage 2 execution model as the other platform
components. Windows does not need local `kubectl` or `helm`.

```powershell
. .\scripts\lab-config.ps1
.\scripts\deploy.ps1 harbor
.\scripts\deployment-status.ps1 harbor
.\scripts\harbor-admin.ps1
```

Pinned:

```text
Harbor Helm chart: 1.19.1
Harbor app:        2.15.1
```

## Harbor storage final correction

For this testing lab, Harbor uses the K3s `local-path` StorageClass rather than
Longhorn. This supersedes earlier Harbor Longhorn storage guidance.

```text
registry   2Gi local-path
database   1Gi local-path
redis      1Gi local-path
jobservice 1Gi local-path
trivy      1Gi local-path
```

Use:

```powershell
.\scripts\remove-deployment.ps1 harbor -Force
.\scripts\deploy.ps1 harbor
```

to recreate a fresh Harbor installation that was previously provisioned with a
Longhorn StorageClass.

## K3s local-storage correction for Harbor

Stage 1 previously disabled the K3s `local-storage` packaged component. That
prevented the `local-path` StorageClass from existing.

New clusters no longer disable `local-storage`.

Existing clusters are repaired automatically during:

```powershell
.\scripts\deploy.ps1 harbor
```

Optional status:

```powershell
.\scripts\k3s-local-storage.ps1 status
```
