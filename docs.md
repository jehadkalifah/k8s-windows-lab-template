# Operational runbook

## Full lifecycle

```powershell
.\scripts\up.ps1
.\scripts\create-golden.ps1
.\scripts\backup.ps1
.\scripts\restore-golden.ps1
.\scripts\destroy.ps1
```

## Kubernetes context

```powershell
.\scripts\get-kubeconfig.ps1
.\scripts\use-kubeconfig.ps1
kubectl get nodes
```

## Golden snapshot

The golden snapshot is VM-level. It is the preferred reset mechanism for local lab work.

Velero is the logical Kubernetes backup mechanism.


## LAN bridge configuration

```powershell
.\scripts\show-bridges.ps1
Copy-Item .\scripts\lab-config.ps1.example .\scripts\lab-config.ps1
notepad .\scripts\lab-config.ps1
.\scripts\up.ps1
```

The host-only addresses remain stable for cluster management. MetalLB service
addresses are allocated from the configured physical-LAN pool.
