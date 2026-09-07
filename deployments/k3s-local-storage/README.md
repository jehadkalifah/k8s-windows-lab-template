# K3s Local Storage

K3s normally includes Rancher's Local Path Provisioner as the `local-storage`
packaged component.

This repo previously disabled it in `ansible/bootstrap-master.sh`. That was
incorrect once Harbor was changed to use the `local-path` StorageClass.

New clusters no longer disable `local-storage`.

Existing clusters are repaired automatically by:

```text
deployments/k3s-local-storage/ensure.sh
```

The helper:

```text
1. checks for StorageClass local-path
2. checks /etc/rancher/k3s/config.yaml
3. removes only "- local-storage" from the disable list when present
4. keeps Traefik and ServiceLB disabled
5. restarts k3s
6. waits for the API and all nodes
7. waits for local-path and rancher.io/local-path
8. shows provisioner status
```

Harbor calls this helper automatically before installation.
