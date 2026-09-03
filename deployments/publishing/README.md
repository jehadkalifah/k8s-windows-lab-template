# Shared Gateway Publishing

All browser-facing Stage 2 services use one Gateway:

```text
Namespace: istio-ingress
Gateway:   public-gateway
Class:     istio
Listener:  http :80
```

The current path map is:

```text
/demo          -> demo/hello
/longhorn/     -> longhorn-system/longhorn-frontend
/grafana       -> monitoring/monitoring-grafana
/prometheus    -> monitoring/monitoring-kube-prometheus-prometheus
/alertmanager  -> monitoring/monitoring-kube-prometheus-alertmanager
/argocd        -> argocd/argocd-server
/minio/        -> velero/minio console
```

Apply/reconcile:

```powershell
.\scripts\publish.ps1 all
```

Status:

```powershell
.\scripts\publishing-status.ps1
```

Remove only HTTPRoutes:

```powershell
.\scripts\unpublish.ps1
```

cert-manager and Velero do not provide their own browser UIs. MinIO is the
browser UI exposed for the Velero lab backup store.


## Trailing-slash and prefix rewrite

Longhorn and MinIO Console are single-page/browser applications that expect
their backend HTTP server to receive root-relative requests.

The shared Gateway therefore uses:

```text
/longhorn  -> 302 /longhorn/
/longhorn/* -> strip /longhorn/ -> longhorn-frontend:80

/minio     -> 302 /minio/
/minio/*   -> strip /minio/ -> minio:9001
```

Use these canonical URLs:

```text
http://<gateway-ip>/longhorn/
http://<gateway-ip>/minio/
```


## Longhorn host-based exception

Longhorn still uses `istio-ingress/public-gateway`, but its UI is served at
the root of a dedicated hostname because the current Longhorn frontend emits
root-level asset and API URLs.

The entry path remains:

```text
http://<gateway-ip>/longhorn
```

and redirects to:

```text
http://longhorn.<gateway-ip-with-dashes>.nip.io/
```

Example:

```text
http://192.168.100.240/longhorn
  -> http://longhorn.192-168-100-240.nip.io/
```

This uses the same Gateway and same MetalLB VIP.

To use private DNS instead, set:

```powershell
$env:LONGHORN_PUBLISH_HOST = "longhorn.lab.local"
```

and make that hostname resolve to the Gateway IP.
