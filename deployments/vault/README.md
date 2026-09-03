# HashiCorp Vault — Stage 2 Component

Pinned versions:

```text
Vault Helm chart: 0.34.1
Vault app:        2.0.4
```

Architecture:

```text
3 Vault server pods
+ Integrated Storage (Raft)
+ 1 x 5Gi Longhorn PVC per Vault pod
+ Vault Agent Injector
+ ClusterIP UI service
```

Install Longhorn first:

```powershell
.\scripts\deploy.ps1 longhorn
```

Then install Vault:

```powershell
.\scripts\deploy.ps1 vault
```

Initialize and form the Raft cluster:

```powershell
.\scripts\vault-init.ps1
```

After a restart, unseal:

```powershell
.\scripts\vault-unseal.ps1
```

Status:

```powershell
.\scripts\deployment-status.ps1 vault
```

Publishing:

```powershell
.\scripts\publish.ps1 vault
```

Vault keeps its data on the `longhorn` StorageClass. Do not commit the root
token or unseal key into this repository.


## UI before initialization

The Vault UI Service is configured to remain reachable before initialization:

```yaml
ui:
  enabled: true
  publishNotReadyAddresses: true
  activeVaultPodOnly: false
```

This prevents the shared Gateway from returning `no healthy upstream` while
Vault is still uninitialized/sealed.

After deployment and publishing:

```powershell
.\scripts\publish.ps1 vault
```

open:

```text
http://<gateway-ip>/vault
```

which redirects to the Vault hostname on the same `public-gateway`.

You can initialize Vault from the UI, but the preferred repo workflow is:

```powershell
.\scripts\vault-init.ps1
```

because it initializes `vault-0`, joins `vault-1` and `vault-2` to the Raft
cluster, and unseals all three nodes.
