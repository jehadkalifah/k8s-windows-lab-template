# Harbor Private Registry for the CI/CD Lab

Pinned deployable pair:

```text
Harbor Helm chart: 1.19.1
Harbor app:        2.15.1
```

Harbor is optional. The original OCIR examples remain in this repository.
Harbor is the recommended local/private registry when you want a UI and a
realistic registry workflow.

Lab URL:

```text
http://harbor.192-168-100-240.nip.io
```

Install:

```powershell
.\scripts\harbor-install.ps1
```

Status:

```powershell
.\scripts\harbor-status.ps1
```

Remove workloads but keep data:

```powershell
.\scripts\harbor-remove.ps1
```

Destroy test data too:

```powershell
.\scripts\harbor-remove.ps1 -DeleteData
```

The lab values use Longhorn PVCs and enable Harbor's Trivy scanner. Because the
existing shared Gateway currently exposes HTTP only, this example is an HTTP
lab registry. Do not copy that transport choice to production.
