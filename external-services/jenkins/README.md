# Jenkins External VM

Jenkins is intentionally **not** deployed inside Kubernetes.

```text
Vagrant / VirtualBox VM
  name:        jenkins
  management:  192.168.56.20
  LAN backend: 192.168.100.220
  HTTP port:   8080
  context:     /jenkins
```

Jenkins LTS is pinned to:

```text
2.568.3
```

Start/provision:

```powershell
.\scripts\jenkins-up.ps1
```

Initial password:

```powershell
.\scripts\jenkins-password.ps1
```

Publish through the existing Istio Gateway:

```powershell
.\scripts\publish.ps1 jenkins
```

Open:

```text
http://192.168.100.240/jenkins
```

Kubernetes does not run Jenkins. It only represents the VM as:

```text
Service (no selector)
  -> EndpointSlice
  -> 192.168.100.220:8080
```

and the shared HTTPRoute forwards `/jenkins` to that Service.
