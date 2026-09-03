# Kubernetes Windows Lab Template

A reproducible Windows lab with **VirtualBox + Vagrant + K3s**:

- 1 K3s control-plane node
- 2 K3s worker nodes
- Longhorn persistent storage
- MetalLB on the physical LAN
- Istio + Kubernetes Gateway API
- MinIO + Velero backup/restore
- VM restore points and Kubernetes restore points
- Remote Kubernetes API access from another laptop on `192.168.10.x`

> Development/lab use only. This is not a production HA design.

---

## Network design

```text
Windows / VirtualBox host
│
├── k3s-master
│   ├── K3s management: 192.168.56.10
│   └── Physical LAN:    192.168.10.210
│
├── k3s-worker1
│   ├── K3s management: 192.168.56.11
│   └── Physical LAN:    192.168.10.211
│
└── k3s-worker2
    ├── K3s management: 192.168.56.12
    └── Physical LAN:    192.168.10.212
```

Each VM has:

```text
NIC 1  NAT          -> internet access
NIC 2  Host-only    -> stable K3s internal network 192.168.56.0/24
NIC 3  Bridged LAN  -> physical 192.168.10.0/24 network
```

Remote Kubernetes API:

```text
https://192.168.10.210:6443
```

MetalLB application range:

```text
192.168.10.240-192.168.10.245
```

The K3s API certificate includes `192.168.10.210` as a TLS SAN.

---

# First-time setup

## 1. Install prerequisites

Install:

1. VirtualBox
2. Vagrant
3. Git for Windows

Recommended host capacity:

```text
CPU:  8 logical cores or more
RAM:  16 GB minimum; 24 GB+ recommended
Disk: 100 GB+ SSD free
```

## 2. Open PowerShell in the repo

```powershell
cd D:\k8s-windows-lab-template
```

## 3. Unblock downloaded scripts

Run once after extracting the ZIP:

```powershell
.\scripts\prepare.cmd
```

## 4. Find the physical bridged adapter

```powershell
.\scripts\show-bridges.ps1
```

Example:

```text
TP-Link Wireless USB Adapter
Realtek PCIe GbE Family Controller
```

`show-bridges.ps1` only lists adapters. It does **not** load the selected adapter into PowerShell.

## 5. Configure `lab-config.ps1`

The provided configuration is:

```powershell
$env:K8S_BRIDGE_ADAPTER = "TP-Link Wireless USB Adapter"

$env:K3S_MASTER_LAN_IP  = "192.168.10.210"
$env:K3S_WORKER1_LAN_IP = "192.168.10.211"
$env:K3S_WORKER2_LAN_IP = "192.168.10.212"

$env:K3S_API_LAN_IP = "192.168.10.210"

$env:METALLB_POOL_START = "192.168.10.240"
$env:METALLB_POOL_END   = "192.168.10.245"
```

Edit if necessary:

```powershell
notepad .\scripts\lab-config.ps1
```

Reserve/exclude these IPs from your router DHCP pool.

---

# Important: first command in every new PowerShell session

Run:

```powershell
. .\scripts\lab-config.ps1
```

The leading **dot + space** is required. It dot-sources the variables into the current PowerShell session.

Verify:

```powershell
$env:K8S_BRIDGE_ADAPTER
$env:K3S_MASTER_LAN_IP
$env:K3S_API_LAN_IP
$env:METALLB_POOL_START
$env:METALLB_POOL_END
```

Expected:

```text
TP-Link Wireless USB Adapter
192.168.10.210
192.168.10.210
192.168.10.240
192.168.10.245
```

---

# Validate the repository before creating the cluster

This release specifically removes the old Ansible/Vagrant private-key problem.

Run:

```powershell
.\scripts\validate-repo.cmd
```

Expected:

```text
PASS: Ansible inventory contains no Vagrant private-key dependency.
PASS: Ansible platform configuration runs locally on k3s-master.
PASS: up.ps1 invokes the local platform playbook.
Repository validation passed.
```

The Ansible platform playbook runs **locally inside `k3s-master`**. It does not SSH from the master to the Vagrant VMs and does not use paths such as:

```text
/vagrant/.vagrant/machines/.../private_key
```

The Vagrant shell provisioners already configure the workers and join them to K3s.

---

# Create the cluster

## 1. Load configuration

```powershell
. .\scripts\lab-config.ps1
```

## 2. Create/provision

```powershell
.\scripts\up.ps1
```

or, if PowerShell policy blocks `.ps1`:

```powershell
.\scripts\up.cmd
```

The sequence is:

```text
1. Create/provision k3s-master
2. Install K3s server and create join token
3. Create/provision k3s-worker1 and join K3s
4. Create/provision k3s-worker2 and join K3s
5. Run Ansible LOCALLY on k3s-master
6. Install Longhorn, MetalLB, Istio, Gateway API, MinIO, Velero
7. Generate local + remote kubeconfigs
```

## 3. Check cluster status

```powershell
.\scripts\status.ps1
```

or:

```powershell
vagrant ssh k3s-master -c "sudo kubectl get nodes -o wide"
```

Expected:

```text
k3s-master
k3s-worker1
k3s-worker2
```

---

# Kubeconfig

Two files are generated:

```text
.kube\lab-kubeconfig.yaml
.kube\remote-kubeconfig.yaml
```

Local host API:

```text
https://192.168.56.10:6443
```

Remote LAN API:

```text
https://192.168.10.210:6443
```

From another laptop on `192.168.10.x`:

```powershell
Test-NetConnection 192.168.10.210 -Port 6443
```

Then copy `remote-kubeconfig.yaml` to that laptop and run:

```powershell
$env:KUBECONFIG="$HOME\.kube\k3s-lab.yaml"
kubectl get nodes
```

---

# MetalLB / application access

MetalLB uses:

```text
192.168.10.240-192.168.10.245
```

Traffic flow:

```text
LAN client
   |
MetalLB IP 192.168.10.240-245
   |
Istio Gateway
   |
Gateway API / HTTPRoute
   |
Kubernetes Service
   |
Pods
```

Check:

```powershell
vagrant ssh k3s-master -c "sudo kubectl get svc -A"
```

---

# Lifecycle commands

## Start existing lab without provisioning

```powershell
. .\scripts\lab-config.ps1
.\scripts\run.ps1
```

## Graceful power off

```powershell
.\scripts\down.ps1
```

Keeps VM disks, K3s state, Longhorn data, and snapshots.

## Suspend

```powershell
.\scripts\suspend.ps1
```

## Resume

```powershell
. .\scripts\lab-config.ps1
.\scripts\resume.ps1
```

## Permanent destroy

```powershell
.\scripts\destroy.cmd
```

Type:

```text
DESTROY
```

`destroy` uses `VBoxManage` directly and removes only:

```text
k3s-master
k3s-worker1
k3s-worker2
```

It also cleans:

```text
.vagrant\
.kube\
.k3s-token
```

It keeps:

```text
scripts\lab-config.ps1
```

---

# Restore points

Create both VM and Velero restore points:

```powershell
. .\scripts\lab-config.ps1
.\scripts\restore-point.ps1 create golden-clean -Level both
```

List:

```powershell
.\scripts\restore-point.ps1 list
```

Restore exact VM state:

```powershell
. .\scripts\lab-config.ps1
.\scripts\restore-point.ps1 restore golden-clean -Level vm
```

Restore Kubernetes only:

```powershell
.\scripts\restore-point.ps1 restore golden-clean -Level cluster
```

---

# Velero note

MinIO is inside this local cluster, so a complete VM destroy also removes the local MinIO/Velero backups.

For backups that must survive complete lab destruction, use external storage such as:

```text
OCI Object Storage S3-compatible API
AWS S3
External MinIO
```

---

# Troubleshooting

## Old Ansible private-key error

If you see something like:

```text
no such identity: /vagrant/.vagrant/machines/k3s-master/virtualbox/private_key
Permission denied (publickey,password)
```

then you are using an older repo.

This release should pass:

```powershell
.\scripts\validate-repo.cmd
```

and `ansible\inventory.ini` should contain only:

```ini
[local]
localhost ansible_connection=local ansible_python_interpreter=/usr/bin/python3
```

## Bridge variable not loaded

Run:

```powershell
. .\scripts\lab-config.ps1
```

then:

```powershell
$env:K8S_BRIDGE_ADAPTER
```

## Remote API not reachable

```powershell
Test-NetConnection 192.168.10.210 -Port 6443
```

On master:

```powershell
vagrant ssh k3s-master -c "ip -br -4 addr"
vagrant ssh k3s-master -c "sudo ss -lntp | grep 6443"
```

Check router DHCP exclusions, firewall rules, and Wi-Fi client isolation.

---

# Version pins

```yaml
k3s_version: "v1.36.1+k3s1"
istio_version: "1.31.0"
gateway_api_version: "v1.6.0"
longhorn_version: "1.12.1"
metallb_version: "0.16.1"
velero_chart_version: "12.1.0"
```

---

## License

MIT.
