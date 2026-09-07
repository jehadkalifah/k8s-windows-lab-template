# Harbor Private Registry

Harbor is installed as a normal Stage 2 component using the same execution
model as Vault, Longhorn, Kiali, Keycloak and the other platform modules.

Windows does **not** need local `kubectl` or `helm`.

Pinned versions:

```text
Harbor Helm chart: 1.19.1
Harbor app:        2.15.1
```

Install:

```powershell
. .\scripts\lab-config.ps1
.\scripts\deploy.ps1 harbor
```

Compatibility wrapper:

```powershell
.\scripts\harbor-install.ps1
```

Status:

```powershell
.\scripts\deployment-status.ps1 harbor
```

Admin password:

```powershell
.\scripts\harbor-admin.ps1
```

Remove while preserving data:

```powershell
.\scripts\remove-deployment.ps1 harbor
```

Delete Harbor and PVCs:

```powershell
.\scripts\remove-deployment.ps1 harbor -Force
```

Default URL:

```text
http://harbor.192-168-100-240.nip.io/
```


## Harbor-specific Longhorn StorageClass

Harbor uses a dedicated StorageClass:

```text
longhorn-harbor
numberOfReplicas = 1
```

The platform default `longhorn` StorageClass remains unchanged at two replicas.

This is intentional for the local lab because Harbor is a disposable testing
registry and its five PVCs can otherwise consume too much replicated capacity.

Current Harbor lab PVC requests:

```text
registry:   2Gi
jobservice: 1Gi
database:   1Gi
redis:      1Gi
trivy:      1Gi
```

Total logical Harbor storage:

```text
6Gi
```

Because Harbor uses one Longhorn replica, the requested replica capacity is
approximately 6Gi rather than approximately 20Gi with the earlier two-replica
configuration.

If Harbor PVCs already exist using `longhorn`, the installer intentionally
stops and tells you to recreate the fresh Harbor installation:

```powershell
.\scripts\remove-deployment.ps1 harbor -Force
.\scripts\deploy.ps1 harbor
```

Do this only when there is no Harbor data you need to preserve.

## Final Harbor lab storage: K3s local-path

Harbor no longer uses Longhorn in this local lab.

The one-replica `longhorn-harbor` approach still required Longhorn to find
enough free schedulable capacity for one replica. On the current lab, the
registry volume could still remain detached with:

```text
ReplicaSchedulingFailure
disks are unavailable; insufficient storage
```

The final Harbor lab configuration uses:

```text
StorageClass: local-path
Provisioner:  rancher.io/local-path
```

for all five Harbor PVCs:

```text
registry:   2Gi
jobservice: 1Gi
database:   1Gi
redis:      1Gi
trivy:      1Gi
```

This avoids Longhorn replica scheduling completely and keeps Longhorn capacity
available for Vault, Keycloak and the other platform workloads.

Tradeoff: K3s `local-path` storage is node-local and is therefore not an HA
storage design. That is acceptable for this disposable testing registry.

If existing Harbor PVCs use `longhorn` or `longhorn-harbor`, and there is no
Harbor data to preserve:

```powershell
.\scripts\remove-deployment.ps1 harbor -Force
.\scripts\deploy.ps1 harbor
```

The installer now refuses to continue if old Harbor PVCs use another
StorageClass.

## Automatic K3s local-storage repair

The repo previously disabled K3s `local-storage` in Stage 1. Harbor now invokes:

```text
/vagrant/deployments/k3s-local-storage/ensure.sh
```

before Helm installation.

If `local-path` is missing, the helper removes only `local-storage` from the
K3s disable list, restarts K3s, waits for the API/nodes/StorageClass, verifies
`rancher.io/local-path`, and then allows Harbor to continue.

No manual Windows `kubectl` or `helm` commands are required.

## Rendered StorageClass validation correction

The Harbor Helm chart does not render every persistent volume declaration with
identical YAML formatting.

Some standalone PVCs can render:

```yaml
storageClassName: local-path
```

while StatefulSet `volumeClaimTemplates`, including components such as Trivy,
can render:

```yaml
storageClassName: "local-path"
```

The earlier installer incorrectly counted only the unquoted form:

```text
storageClassName: local-path
```

which could report only two matches and stop before installation even though
all Harbor persistence values correctly selected `local-path`.

The installer now validates in two stages:

```text
1. values.yaml:
   exactly five Harbor storageClass: local-path selections

2. helm template output:
   at least five storageClassName references matching either:
   local-path
   "local-path"
```

If rendered validation fails, the installer prints every
`storageClassName:` line for immediate troubleshooting.

After Helm installation, it also verifies that all actual Harbor PVCs use
`local-path` and that at least five Harbor PVCs exist.
