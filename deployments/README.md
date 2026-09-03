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
istio
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
