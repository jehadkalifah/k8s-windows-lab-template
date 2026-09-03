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
