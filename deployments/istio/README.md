# Istio Ingress — Stage 2 Component

Install:

```powershell
. .\scripts\lab-config.ps1
.\scripts\deploy.ps1 istio
```

This module installs:

1. Gateway API `v1.6.0`
2. MetalLB `v0.16.1`
3. Istio base `1.31.0`
4. istiod `1.31.0`
5. an Istio-managed Gateway
6. demo app
7. HTTPRoute

Status:

```powershell
.\scripts\deployment-status.ps1 istio
```

The Gateway uses:

```yaml
gatewayClassName: istio
```

and should receive a MetalLB address from:

```text
192.168.100.240-192.168.100.245
```


## MetalLB validating webhook

Before creating the L2 CRs, the installer now verifies that
`metallb-webhook-service` is reachable from `k3s-master`.

Diagnostic command:

```powershell
.\scripts\metallb-webhook-check.ps1
```

If the webhook was temporarily unavailable, simply rerun:

```powershell
.\scripts\deploy.ps1 istio
```

The deployment uses Helm upgrade/install and `kubectl apply`, so rerunning it is
safe for this lab.


## Istio Helm profile note

The Stage 2 installer uses the standard Istio `istiod` Helm chart defaults.

Do not pass `profile=minimal` to the Istio 1.31 `istiod` Helm chart in this
lab. The installer performs `helm template` first and then runs
`helm upgrade --install`.

The Kubernetes Gateway API `Gateway` is still used for ingress; Istio
automatically provisions its gateway Deployment and Service from the
`gatewayClassName: istio` resource.
