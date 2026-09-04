# Keycloak Operator + PostgreSQL — Stage 2 Component

Pinned versions:

```text
Keycloak / Operator: 26.7.3
PostgreSQL:          18
```

Persistence:

```text
PostgreSQL StatefulSet
  -> data-keycloak-postgres-0
  -> 5Gi
  -> StorageClass: longhorn
```

Keycloak itself does not need a PVC because realms, users, clients and sessions
that require durable database state are stored in PostgreSQL.

Install:

```powershell
.\scripts\deploy.ps1 keycloak
```

Status:

```powershell
.\scripts\deployment-status.ps1 keycloak
```

Publishing:

```powershell
.\scripts\publish.ps1 keycloak
```

Open:

```text
http://<gateway-ip>/keycloak
```

Retrieve the operator-generated temporary admin credentials:

```powershell
.\scripts\keycloak-admin.ps1
```

Removal is protected while the database PVC exists:

```powershell
.\scripts\remove-deployment.ps1 keycloak
```

Intentional destructive removal:

```powershell
.\scripts\remove-deployment.ps1 keycloak -Force
```

