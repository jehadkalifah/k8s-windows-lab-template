# cert-manager — Stage 2 Component

This module installs cert-manager as an independent Stage 2 component.

Pinned version:

```text
v1.21.1
```

Install:

```powershell
. .\scripts\lab-config.ps1
.\scripts\deploy.ps1 cert-manager
```

Status:

```powershell
.\scripts\deployment-status.ps1 cert-manager
```

Remove the Helm release but keep CRDs:

```powershell
.\scripts\remove-deployment.ps1 cert-manager
```

Remove cert-manager and its CRDs:

```powershell
.\scripts\remove-deployment.ps1 cert-manager -PurgePrerequisites
```

The installer also creates a small local self-signed test Certificate in:

```text
cert-manager-test
```

This verifies that the cert-manager controllers, webhook, CRDs, Issuer and
Certificate resources are working.

The self-signed test is for lab verification only. It is not intended to be a
trusted production certificate authority.

Later, cert-manager can be used with Istio Gateway API to automate TLS
certificates for HTTPS listeners.
