# Argo CD — Stage 2 Component

Pinned Helm chart:

```text
10.4.0
```

Install:

```powershell
.\scripts\deploy.ps1 argocd
```

UI:

```powershell
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

Open `https://127.0.0.1:8080`.

Username: `admin`.

Initial password:

```powershell
vagrant ssh k3s-master -c "sudo kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
```
