# Harbor GitOps Template

This is the Harbor alternative to `gitops-template/`.

It assumes:

```text
Registry host: harbor.192-168-100-240.nip.io
Kubernetes pull Secret: harbor-registry
```

Before Argo CD deploys the application, create the pull Secret in each target
namespace with:

```powershell
.\scripts\create-harbor-pull-secret.ps1 -Namespace demo
```

The example is for the HTTP-only private lab registry. Every K3s node must also
be configured to use the lab HTTP registry using
`kubernetes/harbor/k3s-registries.yaml.example`.
