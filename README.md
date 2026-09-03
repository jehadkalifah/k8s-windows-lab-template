# Kubernetes Windows Lab Template

A reproducible local Kubernetes lab for Windows using:

- Vagrant
- VirtualBox
- Ubuntu 24.04
- K3s Kubernetes v1.36.1
- 1 control-plane + 2 workers
- Longhorn for persistent storage
- MetalLB for local `LoadBalancer` services
- Istio 1.31.0
- Kubernetes Gateway API v1.6.0 (Istio-managed GatewayClass)
- Velero for Kubernetes/PV backup and restore
- MinIO as local S3-compatible backup storage
- PowerShell scripts for create, clean snapshot, restore, reset, and destroy

The goal is to make the environment portable: clone the repository on another Windows machine, run the setup script, and get the same lab topology.

## Architecture

```text
Windows 11
   |
   +-- VirtualBox
        |
        +-- Vagrant
             |
             +-- k3s-master   192.168.56.10
             |     Control plane + embedded etcd
             |
             +-- k3s-worker1  192.168.56.11
             |
             +-- k3s-worker2  192.168.56.12
             |
             +-- Kubernetes
                   |
                   +-- MetalLB
                   |     LoadBalancer IPs:
                   |     192.168.56.240-250
                   |
                   +-- Longhorn
                   |     PV / PVC
                   |
                   +-- Istio
                   |     Gateway API / HTTPRoute
                   |     (Gateway API provisions the gateway Service)
                   |
                   +-- MinIO
                   |     Velero backup object storage
                   |
                   +-- Velero
                         Kubernetes + PV backups
```

## What this repository gives you

### Cluster template

The cluster is always rebuilt from:

- `Vagrantfile`
- `ansible/site.yml`
- Helm installs
- Kubernetes manifests
- version-pinned configuration

### Fast "factory reset"

After the cluster is fully configured, create a VirtualBox/Vagrant snapshot called `golden-clean`.

Later, restore that snapshot to return the three VMs to their clean baseline.

### Portable logical backup

Velero can back up Kubernetes resources and persistent volume data. This is useful for practicing restore/migration separately from VM snapshots.

## Requirements on Windows

Install:

1. Windows 10/11 x64
2. VirtualBox
3. Vagrant
4. Git for Windows

Recommended host resources:

- CPU: 8 logical cores or more
- RAM: 16 GB minimum, 24 GB+ recommended
- SSD: 100 GB+ free

The default VMs use approximately:

- master: 4 vCPU / 6 GB RAM
- worker1: 2 vCPU / 4 GB RAM
- worker2: 2 vCPU / 4 GB RAM

Total: 8 vCPU / 14 GB RAM.

You can override these values through environment variables in `Vagrantfile`.

## Networking design

The lab now uses **three network interfaces per VM**:

```text
Adapter 1: NAT
  -> outbound internet access
  -> apt / Helm / container image downloads

Adapter 2: VirtualBox host-only
  -> stable Kubernetes management network
  -> k3s-master  192.168.56.10
  -> k3s-worker1 192.168.56.11
  -> k3s-worker2 192.168.56.12
  -> Windows kubectl connects to 192.168.56.10:6443

Adapter 3: Bridged adapter
  -> connected directly to your physical LAN
  -> obtains a LAN address by DHCP
  -> carries MetalLB L2 announcements
  -> allows other devices on the same LAN to reach Kubernetes LoadBalancer IPs
```

This design keeps cluster management addresses stable while allowing published
services to behave much more like a bare-metal Kubernetes environment.

### Configure the bridged adapter

First list VirtualBox bridged adapters:

```powershell
.\scripts\show-bridges.ps1
```

Create your machine-local configuration:

```powershell
Copy-Item .\scripts\lab-config.ps1.example .\scripts\lab-config.ps1
notepad .\scripts\lab-config.ps1
```

Edit:

```text
scripts\lab-config.ps1
```

Set the exact network adapter name:

```powershell
$env:K8S_BRIDGE_ADAPTER = "Intel(R) Ethernet Connection"
```

or, for example:

```powershell
$env:K8S_BRIDGE_ADAPTER = "Realtek PCIe GbE Family Controller"
```

The exact name depends on the Windows machine.


### VirtualBox PATH is not required

The repository now automatically detects `VBoxManage.exe`.

It first checks Windows `PATH`, then checks the default VirtualBox locations:

```text
C:\Program Files\Oracle\VirtualBox\VBoxManage.exe
C:\Program Files (x86)\Oracle\VirtualBox\VBoxManage.exe
```

Therefore this command should work even if VirtualBox was not added to `PATH`:

```powershell
.\scripts\show-bridges.ps1
```

If VirtualBox is installed in a custom directory, update:

```text
scripts\find-vboxmanage.ps1
```

and add the custom path to the candidate list.


### Configure the MetalLB LAN pool

Assume your LAN is:

```text
Network:      192.168.1.0/24
Router:       192.168.1.1
Router DHCP:  192.168.1.50-192.168.1.199
```

Reserve an unused range outside DHCP, for example:

```text
192.168.1.220-192.168.1.230
```

Then configure:

```powershell
$env:METALLB_POOL_START = "192.168.1.220"
$env:METALLB_POOL_END   = "192.168.1.230"
```

MetalLB will allocate `LoadBalancer` service IPs from that LAN range.

> Never configure MetalLB with IPs that your router can assign through DHCP.
> Reserve/exclude the selected addresses in the router, or choose an unused
> range outside the DHCP pool.

### Publishing flow

With the bridged design:

```text
PC / phone / server on your LAN
             |
             | http(s)://192.168.1.220
             v
       Physical LAN
             |
       MetalLB (L2)
             |
     LoadBalancer Service
             |
       Istio Gateway
             |
       Gateway API
        / HTTPRoute
             |
     Kubernetes Service
             |
            Pods
```

That means a laptop, phone, VM or another physical host on the same LAN can
reach the Kubernetes service through the MetalLB IP, subject to normal LAN,
firewall and Wi-Fi/client-isolation rules.

### Portable across Windows machines

The physical adapter name and LAN range are deliberately **not committed to Git**.

Each Windows machine creates its own:

```text
scripts\lab-config.ps1
```

This file is excluded by `.gitignore`.

So the same Git repository can be reused on:

```text
Machine A -> Intel adapter + 192.168.1.220-230
Machine B -> Realtek adapter + 10.0.0.220-230
Machine C -> Wi-Fi adapter + 172.16.10.220-230
```

without changing the repository itself.

## Quick start

Open PowerShell in the repository directory.

### 1. Create the cluster

```powershell
.\scripts\up.ps1
```

The script:

1. Starts the three VMs.
2. Installs K3s.
3. Joins the workers.
4. Runs the Ansible post-installation.
5. Installs Longhorn, MetalLB, Istio, Gateway API, MinIO and Velero.
6. Waits for the main components.
7. Prints useful access information.

### 2. Verify

```powershell
vagrant ssh k3s-master -c "sudo kubectl get nodes -o wide"
vagrant ssh k3s-master -c "sudo kubectl get pods -A"
```

Expected nodes:

```text
k3s-master
k3s-worker1
k3s-worker2
```

### 3. Configure the golden clean snapshot

Do this only after `up.ps1` completes successfully:

```powershell
.\scripts\create-golden.ps1
```

This creates `golden-clean` snapshots for all three VMs.

### 4. Reset to the clean snapshot

```powershell
.\scripts\restore-golden.ps1
```

After the restore, validate:

```powershell
vagrant ssh k3s-master -c "sudo kubectl get nodes"
vagrant ssh k3s-master -c "sudo kubectl get pods -A"
```

## Velero backup/restore

Velero uses the MinIO service as an S3-compatible backup target.

Create a backup:

```powershell
.\scripts\backup.ps1
```

List backups:

```powershell
vagrant ssh k3s-master -c "velero backup get"
```

Restore:

```powershell
.\scripts\restore-velero.ps1
```

The default logical backup name is `lab-clean-backup`.

> VM snapshots and Velero backups serve different purposes. The VM snapshot is the fastest full lab rollback. Velero is the Kubernetes-native recovery/migration mechanism.

## Test application

A simple sample application is included:

```powershell
vagrant ssh k3s-master -c "sudo kubectl apply -f /vagrant/manifests/demo.yaml"
```

Then:

```powershell
vagrant ssh k3s-master -c "sudo kubectl -n demo get pods,pvc,svc,gateway,httproute"
```

The demo creates:

- Namespace
- PVC using Longhorn
- Deployment
- ClusterIP Service
- Gateway API `Gateway`
- `HTTPRoute`

If you create a `LoadBalancer` service, MetalLB can allocate an address from `192.168.56.240-250`.

## Accessing the Kubernetes API from Windows

The kubeconfig is copied from the master VM to:

```text
<template-folder>.kube\lab-kubeconfig.yaml
```

The server address is rewritten to:

```text
https://192.168.56.10:6443
```

Use:

```powershell
$env:KUBECONFIG="$PWD\.kube\lab-kubeconfig.yaml"
kubectl get nodes
```

If you already have `KUBECONFIG`, restore your previous value after the session:

```powershell
Remove-Item Env:KUBECONFIG
```

## Useful commands

### SSH

```powershell
vagrant ssh k3s-master
vagrant ssh k3s-worker1
vagrant ssh k3s-worker2
```

### Cluster status

```powershell
.\scripts\status.ps1
```

### Halt

```powershell
vagrant halt
```

### Start again

```powershell
vagrant up
```
## Repository layout

```text
k8s-windows-lab/
├── README.md
├── .gitignore
├── Vagrantfile
├── ansible/
│   ├── inventory.ini
│   ├── site.yml
│   ├── group_vars/
│   │   └── all.yml
│   ├── roles/
│   │   ├── common/
│   │   ├── k3s_server/
│   │   ├── k3s_agent/
│   │   └── platform/
│   └── templates/
│       ├── metallb-config.yaml.j2
│       ├── velero-values.yaml.j2
│       └── minio.yaml.j2
├── manifests/
│   └── demo.yaml
├── scripts/
│   ├── up.ps1
│   ├── create-golden.ps1
│   ├── restore-golden.ps1
│   ├── restore-point.ps1
│   ├── vm-points.ps1
│   ├── cluster-points.ps1
│   ├── backup.ps1
│   ├── restore-velero.ps1
│   ├── status.ps1
│   └── destroy.ps1
└── .kube/
```

## Version pins

The template intentionally pins core versions in Ansible variables:

```yaml
k3s_version: "v1.36.1+k3s1"
istio_version: "1.31.0"
gateway_api_version: "v1.6.0"
longhorn_version: "1.12.1"
metallb_version: "0.16.1"
velero_chart_version: "12.1.0"
```

Update these deliberately after checking compatibility instead of silently tracking latest releases.

## Notes and limitations

### This is a development/lab cluster

It is not intended to be a production HA design.

There is only one control-plane node. If it fails, Kubernetes control-plane availability is lost.

### Persistent storage

Longhorn runs on the worker VM disks. For a stronger storage lab, increase worker disk sizes and use more replicas.

### LoadBalancer

MetalLB is suitable for this bare-metal-style local network. It is not a substitute for a cloud provider load balancer.

### Istio

The template uses the Kubernetes Gateway API with Istio. The Gateway API CRDs are installed before Istio.

### Backup storage

MinIO is intentionally local to keep the project self-contained. For a real disaster-recovery design, put Velero backups in storage outside the cluster.

## License

Use and modify this repository for your own lab and learning environment.


## First-run sequence

Run these in order:

```powershell
.\scripts\up.ps1
.\scripts\create-golden.ps1
```

The second command creates the VM-level factory-reset point. After that, normal experimentation can be reset with:

```powershell
.\scripts\restore-golden.ps1
```

For logical Kubernetes backup/restore testing:

```powershell
.\scripts\backup.ps1
.\scripts\restore-velero.ps1
```

## Why both snapshot and Velero?

A VirtualBox snapshot is the fastest way to return all three local VMs to the exact captured baseline, including their local Longhorn state.

Velero is different: it backs up Kubernetes resources and persistent data through Kubernetes/Velero mechanisms. It is the mechanism to practice cluster migration/disaster recovery. Its backup target in this self-contained lab is MinIO inside the cluster, so a full VM destruction also destroys those local backups. For durable backup, configure an external S3-compatible bucket.

## External access example

The demo `Gateway` uses Istio's `GatewayClass` and Gateway API. When it is created, Istio provisions the corresponding gateway deployment/service. Check it with:

```powershell
kubectl get gateway -n demo
kubectl get svc -n demo
```

A `LoadBalancer` service can receive an address from MetalLB:

```powershell
kubectl get svc -A | Select-String LoadBalancer
```

The allocated address should be within:

```text
192.168.56.240-192.168.56.250
```


# Multiple Restore Points

The lab supports **many named restore points**. You can keep restore points such as:

```text
golden-clean
after-istio
app-v1
app-v2
before-upgrade
after-upgrade
testing-longhorn
```

There are two independent recovery layers.

## VM restore points — exact lab rollback

VM restore points use VirtualBox snapshots through Vagrant. They capture all three virtual machines:

```text
k3s-master
k3s-worker1
k3s-worker2
```

This includes Linux state, K3s state, Kubernetes state, installed software, configuration, and local Longhorn data.

### Create

```powershell
.\scripts\vm-points.ps1 create before-upgrade
```

### List

```powershell
.\scripts\vm-points.ps1 list
```

Example:

```text
=== k3s-master ===
golden-clean
app-v1
before-upgrade

=== k3s-worker1 ===
golden-clean
app-v1
before-upgrade

=== k3s-worker2 ===
golden-clean
app-v1
before-upgrade
```

### Restore any VM restore point

```powershell
.\scripts\vm-points.ps1 restore app-v1
```

The script halts the VMs, restores the same named snapshot on all three nodes, starts them again, refreshes kubeconfig and displays cluster status.

### Delete

```powershell
.\scripts\vm-points.ps1 delete app-v1
```

## Cluster restore points — Velero

Cluster restore points use Velero and are intended for Kubernetes-level recovery, migration and DR testing.

They can contain Kubernetes resources and persistent-volume data, including:

```text
Namespaces
Deployments
StatefulSets
DaemonSets
Services
ConfigMaps
Secrets
Gateway API objects
Istio resources
CRDs
PVC/PV application data
```

### Create

```powershell
.\scripts\cluster-points.ps1 create app-v1
```

### List all cluster restore points

```powershell
.\scripts\cluster-points.ps1 list
```

Example:

```text
NAME             STATUS
golden-clean     Completed
app-v1           Completed
app-v2           Completed
before-upgrade   Completed
```

### Inspect one

```powershell
.\scripts\cluster-points.ps1 describe app-v1
```

### Restore one

```powershell
.\scripts\cluster-points.ps1 restore app-v1
```

A uniquely named Velero restore operation is created so the original backup remains available for future restores.

### Delete

```powershell
.\scripts\cluster-points.ps1 delete app-v1
```

## Recommended combined command

The easiest interface is `restore-point.ps1`.

### Create both VM and cluster restore points

```powershell
.\scripts\restore-point.ps1 create before-upgrade -Level both
```

Conceptually this creates:

```text
before-upgrade
    |
    +-- VM restore point
    |     +-- k3s-master
    |     +-- k3s-worker1
    |     +-- k3s-worker2
    |
    +-- Velero cluster backup
          +-- Kubernetes resources
          +-- backed-up persistent data
```

### List everything

```powershell
.\scripts\restore-point.ps1 list
```

### Restore the exact VM/lab state

```powershell
.\scripts\restore-point.ps1 restore before-upgrade -Level vm
```

Use VM restore when K3s, node configuration, Longhorn or the overall environment is damaged.

### Restore only Kubernetes state/data

```powershell
.\scripts\restore-point.ps1 restore before-upgrade -Level cluster
```

Use cluster restore when the underlying VMs and K3s cluster are healthy.

### Delete both copies

```powershell
.\scripts\restore-point.ps1 delete before-upgrade -Level both
```

`restore -Level both` is intentionally blocked because an exact VM rollback and a Velero logical restore are different recovery mechanisms. Pick one.

## Suggested restore-point lifecycle

After the initial build:

```powershell
.\scripts\up.ps1
.\scripts\restore-point.ps1 create golden-clean -Level both
```

After configuring or testing something important:

```powershell
.\scripts\restore-point.ps1 create after-istio -Level both
.\scripts\restore-point.ps1 create app-v1 -Level both
.\scripts\restore-point.ps1 create before-upgrade -Level both
```

See everything:

```powershell
.\scripts\restore-point.ps1 list
```

Return the complete lab to `app-v1`:

```powershell
.\scripts\restore-point.ps1 restore app-v1 -Level vm
```

Or restore only the Kubernetes backup:

```powershell
.\scripts\restore-point.ps1 restore app-v1 -Level cluster
```

## Which restore should I choose?

| Requirement | VM snapshot | Velero |
|---|---:|---:|
| Exact rollback of all VMs | Yes | No |
| Recover broken K3s | Yes | No |
| Roll back OS/node configuration | Yes | No |
| Restore Kubernetes objects | Yes | Yes |
| Restore backed-up application PV data | Yes | Yes |
| Fast local factory reset | Best | Good |
| Restore into another Kubernetes cluster | No | Yes |
| Kubernetes disaster-recovery practice | Limited | Best |

## Important: where Velero backups are stored

By default, this self-contained lab stores Velero backups in MinIO **inside the same Kubernetes environment**.

This is convenient for lab testing but does not survive complete VM destruction.

If you run:

```powershell
.\scripts\destroy.ps1
```

the local MinIO storage is destroyed along with the VMs.

For backups that must survive full lab destruction, configure Velero with external storage, for example:

```text
AWS S3
OCI Object Storage using its S3-compatible API
external MinIO
another supported S3-compatible object store
```

For ordinary local development and learning, using both **VirtualBox snapshots + Velero backups** gives you the best flexibility.


## Verify LAN publishing

After the cluster is running, deploy the demo:

```powershell
vagrant ssh k3s-master -c "sudo kubectl apply -f /vagrant/manifests/demo.yaml"
```

Check the Gateway and LoadBalancer services:

```powershell
vagrant ssh k3s-master -c "sudo kubectl -n demo get gateway,httproute,svc -o wide"
```

You can also inspect all LoadBalancer services:

```powershell
vagrant ssh k3s-master -c "sudo kubectl get svc -A | grep LoadBalancer"
```

The external IP should come from your configured LAN pool, for example:

```text
192.168.1.220
```

From another device on the same LAN, test:

```text
http://192.168.1.220
```

If it is not reachable, check:

1. the selected VirtualBox bridge is the active physical LAN adapter;
2. the MetalLB pool belongs to the same subnet as that LAN;
3. the addresses are excluded from router DHCP;
4. Windows/host firewall or upstream LAN firewall rules;
5. Wi-Fi access-point client isolation;
6. whether the Gateway/Service received the expected `EXTERNAL-IP`.

### Wi-Fi note

VirtualBox bridged networking over Wi-Fi can depend on the wireless adapter,
driver and access point. Ethernet is generally the most predictable option for
a bare-metal-style MetalLB L2 lab. If your Wi-Fi environment blocks or filters
bridged/L2 behavior, use Ethernet or adjust the local network design.

## Destroy the lab

There are two supported ways to destroy the local Kubernetes lab.

### Recommended: use `destroy.cmd`

From the repository root:

```powershell
.\scripts\destroy.cmd
```

The launcher starts PowerShell with a **process-only execution-policy bypass** and then runs:

```text
scripts\destroy.ps1
```

This avoids the common Windows error:

```text
cannot be loaded because the file is not digitally signed
```

It does **not** permanently change the Windows PowerShell execution policy.

You will be asked to confirm:

```text
This destroys all three VMs and their local cluster data.
Type DESTROY to continue:
```

Type:

```text
DESTROY
```

The script then destroys:

```text
k3s-master
k3s-worker1
k3s-worker2
```

and removes generated local files such as:

```text
.kube\
.k3s-token
```

It intentionally keeps:

```text
scripts\lab-config.ps1
```

so you can rebuild later using the same bridged adapter and MetalLB settings.

### Alternative: run the PowerShell script directly

If PowerShell already allows local scripts:

```powershell
.\scripts\destroy.ps1
```

If Windows blocks the script because it was downloaded from the internet, unblock the repository scripts first:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
```

Then run:

```powershell
.\scripts\destroy.ps1
```

Or allow scripts only for the current PowerShell process:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
.\scripts\destroy.ps1
```

`-Scope Process` applies only to the current PowerShell session and is reset when that window is closed.

### Destroy from inside the `scripts` directory

If your current directory is:

```text
D:\k8s-windows-lab-template\scripts
```

use:

```powershell
.\destroy.cmd
```

or:

```powershell
.\destroy.ps1
```

### Bridge configuration is not required for destroy

Destroying the lab does **not** require:

```text
K8S_BRIDGE_ADAPTER
METALLB_POOL_START
METALLB_POOL_END
```

The `Vagrantfile` intentionally makes the bridged NIC conditional so these commands can still work without loading the LAN configuration:

```text
vagrant destroy
vagrant status
vagrant snapshot list
```

Bridge and MetalLB settings are required only when creating/rebuilding the lab with:

```powershell
.\scripts\up.ps1
```

### Rebuild after destroy

Your local configuration remains in:

```text
scripts\lab-config.ps1
```

To recreate the complete lab:

```powershell
.\scripts\up.ps1
```

### Important data warning

Destroying the VMs also destroys local VM state, including:

```text
K3s cluster state
Longhorn local volume data
VirtualBox VM snapshots
MinIO data stored inside the lab
Velero backups stored in that local MinIO
```

If a backup must survive a complete lab destruction, configure Velero to use external object storage such as OCI Object Storage, AWS S3, or an external MinIO instance.

