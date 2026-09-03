# Kubernetes Windows Lab Template

## Introduction

This repository provides a reusable local Kubernetes lab for Windows using
VirtualBox, Vagrant, Ubuntu and K3s.

The goal is to keep the **virtual-machine/Kubernetes cluster lifecycle**
separate from the **platform and application deployment lifecycle**.

The lab is therefore organized into two stages:

```text
Stage 1 — Base Kubernetes cluster
└── VirtualBox + Vagrant
    └── 3 Ubuntu VMs
        └── K3s
            ├── 1 control-plane node
            ├── 2 worker nodes
            ├── Flannel VXLAN
            ├── CoreDNS
            └── Kubernetes API

Stage 2 — Platform and application deployments
├── Gateway API
├── MetalLB
├── Istio
├── cert-manager
└── additional components added later
```

This design lets you rebuild or troubleshoot the Kubernetes cluster without
mixing that work with Istio, ingress, certificates, storage, monitoring or
application deployments.

The current lab is intended for **development, testing, learning and local
integration work**. It provides a realistic multi-node Kubernetes environment
while remaining easy to create, stop, resume, destroy and rebuild from Windows.

---

## Architecture

```text
                           Physical LAN
                        192.168.100.0/24
                                |
        +-----------------------+-----------------------+
        |                       |                       |
        | bridged eth2          | bridged eth2          | bridged eth2
        v                       v                       v
+----------------+      +----------------+      +----------------+
| k3s-master     |      | k3s-worker1    |      | k3s-worker2    |
|                |      |                |      |                |
| eth0 NAT       |      | eth0 NAT       |      | eth0 NAT       |
| 10.0.2.15      |      | 10.0.2.15      |      | 10.0.2.15      |
|                |      |                |      |                |
| eth1 host-only |<---->| eth1 host-only |<---->| eth1 host-only |
| 192.168.56.10  |      | 192.168.56.11  |      | 192.168.56.12  |
|                |      |                |      |                |
| eth2 LAN       |      | eth2 LAN       |      | eth2 LAN       |
| 192.168.100.210|      |192.168.100.211 |      |192.168.100.212 |
+-------+--------+      +-------+--------+      +-------+--------+
        |                       |                       |
        +----------- Flannel VXLAN on eth1 ------------+
                                |
                         Kubernetes Pods
                          10.42.0.0/16
                                |
                         Kubernetes Services
                          10.43.0.0/16
                                |
                 +--------------+--------------+
                 |                             |
              CoreDNS                       istiod
                 |                             |
                 +-------------+---------------+
                               |
                        Istio Gateway API
                               |
                    LoadBalancer Service
                               |
                          MetalLB L2
                    192.168.100.240-245
                               |
                          LAN clients
```

### Network roles

The three VM interfaces have different responsibilities and must remain
separate:

```text
eth0
  VirtualBox NAT
  Internet/package-download access only
  Typical address inside each VM: 10.0.2.15

eth1
  VirtualBox host-only network
  Kubernetes node-to-node communication
  Flannel VXLAN underlay
  192.168.56.0/24

eth2
  VirtualBox bridged adapter
  Physical LAN access
  Remote Kubernetes API
  MetalLB L2 advertisement
  192.168.100.0/24
```

**Important:** Flannel must explicitly use `eth1`.

```powershell
$env:K3S_FLANNEL_IFACE = "eth1"
```

If Flannel uses the NAT adapter (`eth0`), all VMs can appear as `10.0.2.15`
and cross-node pod networking/DNS will fail.

---

## What Each Tool Does

| Tool / Component | Purpose in this lab |
|---|---|
| **PowerShell** | Main Windows-side interface for creating, starting, stopping, validating and deploying the lab. |
| **VirtualBox** | Runs the three Ubuntu virtual machines and provides NAT, host-only and bridged NICs. |
| **Vagrant** | Defines and manages the VM lifecycle consistently from the repository. |
| **Ubuntu 24.04** | Guest operating system used by all Kubernetes nodes. |
| **K3s** | Lightweight Kubernetes distribution used for the 1-control-plane / 2-worker cluster. |
| **Flannel** | K3s pod-network overlay. In this repo VXLAN is explicitly bound to `eth1` / `192.168.56.0/24`. |
| **CoreDNS** | Kubernetes internal DNS for names such as `kubernetes.default.svc` and `istiod.istio-system.svc`. |
| **Helm** | Installs and upgrades Stage 2 Kubernetes components such as MetalLB, Istio and cert-manager. |
| **Kubernetes Gateway API** | Standard Kubernetes APIs (`GatewayClass`, `Gateway`, `HTTPRoute`) used for ingress routing. |
| **MetalLB** | Provides `LoadBalancer` IP addresses on the physical LAN for bare-metal/local Kubernetes. |
| **Istio** | Provides the ingress gateway/controller and service-mesh control plane. The Gateway API object uses `gatewayClassName: istio`. |
| **cert-manager** | Manages Kubernetes certificates and certificate issuers; later used for HTTPS/TLS on Istio Gateway listeners. |
| **Ansible/bootstrap scripts** | Repository provisioning helpers used during Stage 1 to prepare and validate the base cluster. |
| **Kubeconfig** | Gives Windows or another LAN machine authenticated access to the Kubernetes API. |

---

## Deployment Model

### Stage 1 — Cluster

Stage 1 creates only the reusable Kubernetes foundation:

```text
VirtualBox VMs
Vagrant lifecycle
Ubuntu
K3s server
K3s agents
Flannel
CoreDNS
local kubeconfig
remote kubeconfig
```

Stage 1 intentionally does **not** install the platform components.

### Stage 2 — Platform and applications

Stage 2 contains Kubernetes deployments that can be installed independently.

Current components:

```text
Gateway API
MetalLB
Istio
cert-manager
demo HTTPRoute/application
```

The current ingress path is:

```text
LAN client
    |
    v
MetalLB VIP
192.168.100.240-192.168.100.245
    |
    v
Kubernetes Gateway
gatewayClassName: istio
    |
    v
Istio-managed Gateway
    |
    v
HTTPRoute
    |
    v
Kubernetes Service
    |
    v
Application Pods
```

This modular design makes it possible to add later Stage 2 modules such as
Longhorn, Velero, monitoring, Argo CD and application workloads without
changing the base K3s provisioning workflow.

---

## Network

```text
K3s internal:
  master   192.168.56.10
  worker1  192.168.56.11
  worker2  192.168.56.12

Physical LAN:
  master   192.168.100.210
  worker1  192.168.100.211
  worker2  192.168.100.212

Remote API:
  https://192.168.100.210:6443

MetalLB:
  192.168.100.240-192.168.100.245
```

# Start Every PowerShell Session

Before running any lab command, load the repository configuration into the
current PowerShell session:

```powershell
cd D:\k8s-windows-lab-template
. .\scripts\lab-config.ps1
```

The leading **dot + space** is required because it dot-sources
`lab-config.ps1` into the current PowerShell session.

Verify the complete network configuration:

```powershell
$env:K8S_BRIDGE_ADAPTER
$env:K3S_FLANNEL_IFACE

$env:K3S_MASTER_LAN_IP
$env:K3S_WORKER1_LAN_IP
$env:K3S_WORKER2_LAN_IP
$env:K3S_API_LAN_IP

$env:METALLB_POOL_START
$env:METALLB_POOL_END
```

Expected configuration:

```powershell
$env:K8S_BRIDGE_ADAPTER = "TP-Link Wireless USB Adapter"

# IMPORTANT:
# Flannel must use the host-only K3s inter-node interface.
$env:K3S_FLANNEL_IFACE = "eth1"

$env:K3S_MASTER_LAN_IP  = "192.168.100.210"
$env:K3S_WORKER1_LAN_IP = "192.168.100.211"
$env:K3S_WORKER2_LAN_IP = "192.168.100.212"

$env:K3S_API_LAN_IP = "192.168.100.210"

$env:METALLB_POOL_START = "192.168.100.240"
$env:METALLB_POOL_END   = "192.168.100.245"
```

The VM interface roles are:

```text
eth0 = VirtualBox NAT
       outbound internet only

eth1 = 192.168.56.0/24
       K3s inter-node network
       Flannel VXLAN

eth2 = 192.168.100.0/24
       bridged physical LAN
       remote Kubernetes API + MetalLB
```

Do not change `K3S_FLANNEL_IFACE` to `eth0`. VirtualBox normally assigns
`10.0.2.15` to the NAT interface inside each VM; if Flannel selects that NIC,
cross-node pod networking and cluster DNS will fail.

The correct Flannel result is:

```text
k3s-master  -> 192.168.56.10 dev eth1
k3s-worker1 -> 192.168.56.11 dev eth1
k3s-worker2 -> 192.168.56.12 dev eth1
```

Verify after cluster creation:

```powershell
.\scripts\check-flannel.ps1
```

# Stage 1 — Base K3s Cluster

Run:

```powershell
.\scripts\up.ps1
```

Stage 1 creates only the three-node K3s cluster and kubeconfigs.

It does **not** install Istio, MetalLB, Longhorn, Velero, MinIO, monitoring or applications.

Verify:

```powershell
.\scripts\status.ps1
```

Expected:

```text
k3s-master    Ready
k3s-worker1   Ready
k3s-worker2   Ready
```

# Stage 2 — Deployments

All Kubernetes deployments live in:

```text
deployments\
```

The first component is Istio ingress:

```powershell
.\scripts\deploy.ps1 istio
```

or:

```powershell
.\scripts\deploy.cmd istio
```

## Istio ingress module

It installs in order:

```text
1. Gateway API v1.6.0 standard CRDs
2. MetalLB v0.16.1
3. MetalLB L2 address pool from lab-config.ps1
4. Istio base 1.31.0
5. istiod 1.31.0
6. Istio GatewayClass
7. Kubernetes Gateway API Gateway
8. Demo app
9. HTTPRoute
```

Ingress flow:

```text
LAN client
   |
   v
MetalLB LoadBalancer IP
192.168.100.240-245
   |
   v
Gateway
gatewayClassName: istio
   |
   v
Istio managed gateway
   |
   v
HTTPRoute
   |
   v
demo/hello Service
   |
   v
hello Pods
```

The Gateway uses the standard Kubernetes Gateway API:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
spec:
  gatewayClassName: istio
```

Check deployment:

```powershell
.\scripts\deployment-status.ps1 istio
```

Find ingress IP:

```powershell
vagrant ssh k3s-master -c "sudo kubectl -n istio-ingress get gateway,svc -o wide"
```

Example:

```text
EXTERNAL-IP
192.168.100.240
```

Test from a device on the LAN:

```powershell
curl http://192.168.100.240/
```

Expected:

```text
Hello from K3s + Istio Gateway API
```

If `EXTERNAL-IP` is pending:

```powershell
vagrant ssh k3s-master -c "sudo kubectl -n metallb-system get pods"
vagrant ssh k3s-master -c "sudo kubectl -n metallb-system get ipaddresspool,l2advertisement"
vagrant ssh k3s-master -c "sudo kubectl -n istio-ingress get svc -o wide"
```

The MetalLB pool must be free, outside DHCP, and on the same physical LAN.

## Remove Istio

Keep Gateway API and MetalLB for future Stage 2 modules:

```powershell
.\scripts\remove-deployment.ps1 istio
```

Remove everything including prerequisites:

```powershell
.\scripts\remove-deployment.ps1 istio -PurgePrerequisites
```

# Future Stage 2 Components

The repository is ready for:

```text
deployments/
├── istio/
├── longhorn/
├── velero/
├── monitoring/
├── argocd/
└── applications/
```

Each future component can have:

```text
install.sh
status.sh
remove.sh
manifests/
```

and will be exposed through the same PowerShell deployment dispatcher.

# Lifecycle

Start existing cluster:

```powershell
. .\scripts\lab-config.ps1
.\scripts\run.ps1
```

Graceful shutdown:

```powershell
.\scripts\down.ps1
```

Suspend:

```powershell
.\scripts\suspend.ps1
```

Resume:

```powershell
. .\scripts\lab-config.ps1
.\scripts\resume.ps1
```

Destroy:

```powershell
.\scripts\destroy.cmd
```

# Remote API

```powershell
Test-NetConnection 192.168.100.210 -Port 6443
```

Use the generated:

```text
.kube\remote-kubeconfig.yaml
```

# Validate Repo

```powershell
.\scripts\validate-repo.cmd
```

Expected:

```text
Repository validation passed.
Stage 1: K3s cluster only.
Stage 2: modular deployments; first component = istio.
```

# Pinned Versions

```text
K3s:        v1.36.1+k3s1
Gateway API v1.6.0
MetalLB:    v0.16.1
Istio:      1.31.0
```

---

# Stage 2 Deployment Guidance

This section is an **addition** to the existing cluster setup and lifecycle
documentation above.

Stage 1 remains responsible for creating the base K3s cluster.

Stage 2 is used for everything deployed **on top of Kubernetes**.

Current Stage 2 component:

```text
Istio ingress
```

Future components can be added later without changing the Stage 1 cluster flow.

Example future structure:

```text
deployments/
├── istio/
├── longhorn/
├── velero/
├── monitoring/
├── argocd/
└── applications/
```

---

## Stage 2 prerequisite

Before deploying anything, confirm that Stage 1 is healthy:

```powershell
. .\scripts\lab-config.ps1

.\scripts\status.ps1
```

Expected Kubernetes nodes:

```text
k3s-master    Ready
k3s-worker1   Ready
k3s-worker2   Ready
```

You can also verify directly:

```powershell
vagrant ssh k3s-master -c "sudo kubectl get nodes -o wide"
```

---

## Deploy Istio ingress

Run:

```powershell
.\scripts\deploy.ps1 istio
```

or:

```powershell
.\scripts\deploy.cmd istio
```

The Istio Stage 2 module installs the ingress stack in this order:

```text
1. Kubernetes Gateway API v1.6.0 standard CRDs
2. MetalLB v0.16.1
3. MetalLB L2 address pool
4. Istio base 1.31.0
5. istiod 1.31.0
6. Istio GatewayClass
7. Kubernetes Gateway API Gateway
8. Demo application
9. HTTPRoute
```

The MetalLB address pool comes from:

```text
scripts\lab-config.ps1
```

Current configuration:

```powershell
$env:METALLB_POOL_START = "192.168.100.240"
$env:METALLB_POOL_END   = "192.168.100.245"
```

---

## Istio ingress architecture

```text
Client on physical LAN
192.168.100.x
        |
        | HTTP
        v
MetalLB LoadBalancer IP
192.168.100.240-245
        |
        v
Kubernetes Gateway
gatewayClassName: istio
        |
        v
Istio-managed Gateway proxy
        |
        v
HTTPRoute
        |
        v
Kubernetes Service
        |
        v
Application Pods
```

The Gateway uses the standard Kubernetes Gateway API:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: public-gateway
  namespace: istio-ingress
spec:
  gatewayClassName: istio
  listeners:
    - name: http
      protocol: HTTP
      port: 80
```

The demo route uses:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
```

---

## Check Istio deployment status

Run:

```powershell
.\scripts\deployment-status.ps1 istio
```

or:

```powershell
.\scripts\deployment-status.cmd istio
```

This displays:

```text
Gateway API CRDs
Helm releases
GatewayClass
Istio deployments and pods
MetalLB controller and speakers
MetalLB IPAddressPool
MetalLB L2Advertisement
Istio Gateway
Gateway Service
Demo application
HTTPRoute
```

Useful direct checks:

```powershell
vagrant ssh k3s-master -c "sudo kubectl get gatewayclass"
```

```powershell
vagrant ssh k3s-master -c "sudo kubectl -n istio-system get pods"
```

```powershell
vagrant ssh k3s-master -c "sudo kubectl -n metallb-system get pods"
```

```powershell
vagrant ssh k3s-master -c "sudo kubectl -n istio-ingress get gateway,svc -o wide"
```

```powershell
vagrant ssh k3s-master -c "sudo kubectl -n demo get deployment,pod,svc,httproute -o wide"
```

---

## Find the ingress IP

Run:

```powershell
vagrant ssh k3s-master -c "sudo kubectl -n istio-ingress get svc -o wide"
```

The Gateway Service should receive an address from:

```text
192.168.100.240-192.168.100.245
```

Example:

```text
EXTERNAL-IP
192.168.100.240
```

---

## Test the ingress

From the Windows host or another machine on the same physical LAN:

```powershell
curl http://192.168.100.240/
```

Expected demo response:

```text
Hello from K3s + Istio Gateway API
```

Use the actual `EXTERNAL-IP` returned by Kubernetes rather than assuming it
will always be `.240`.

---

## If the Gateway external IP is pending

Check MetalLB:

```powershell
vagrant ssh k3s-master -c "sudo kubectl -n metallb-system get pods"
```

Check the configured address pool:

```powershell
vagrant ssh k3s-master -c "sudo kubectl -n metallb-system get ipaddresspool,l2advertisement"
```

Check the Gateway Service:

```powershell
vagrant ssh k3s-master -c "sudo kubectl -n istio-ingress get svc -o wide"
```

Verify the configured addresses:

```text
192.168.100.240-192.168.100.245
```

are:

1. in the same physical LAN as the bridged VM NIC;
2. excluded from the router DHCP pool;
3. unused by other devices.

With VirtualBox bridged Wi-Fi, MetalLB L2 reachability can depend on the
wireless adapter and access point. Ethernet bridging is generally more
predictable for MetalLB L2.

---

## Remove Istio deployment

Remove Istio resources while keeping the shared Gateway API CRDs and MetalLB:

```powershell
.\scripts\remove-deployment.ps1 istio
```

This is useful if later Stage 2 components will also use MetalLB or Gateway API.

To completely remove Istio plus the Stage 2 ingress prerequisites:

```powershell
.\scripts\remove-deployment.ps1 istio -PurgePrerequisites
```

This removes:

```text
Demo application
HTTPRoute
Istio Gateway
Istio control plane
MetalLB
Gateway API CRDs
```

---

## Stage 2 directory layout

```text
deployments/
├── README.md
└── istio/
    ├── README.md
    ├── install.sh
    ├── status.sh
    ├── remove.sh
    └── manifests/
        ├── gateway.yaml
        └── demo.yaml
```

The PowerShell deployment interface is:

```text
scripts\deploy.ps1
scripts\deployment-status.ps1
scripts\remove-deployment.ps1
```

Later components can be added to the same deployment framework without
modifying the Stage 1 K3s cluster provisioning process.

---

# Stage 2 Deployment Guidance — cert-manager

cert-manager is added as another independent Stage 2 component.

It does not change Stage 1 cluster provisioning and it does not require Istio
to be installed first.

Pinned version:

```text
cert-manager v1.21.1
```

The repository installs cert-manager from the official OCI Helm chart and
enables its CRDs.

---

## Install cert-manager

At the beginning of a new PowerShell session:

```powershell
. .\scripts\lab-config.ps1
```

Then deploy cert-manager:

```powershell
.\scripts\deploy.ps1 cert-manager
```

or:

```powershell
.\scripts\deploy.cmd cert-manager
```

The deployment performs:

```text
1. Validate the K3s cluster
2. Install Helm if required
3. Install cert-manager
4. Install/manage cert-manager CRDs
5. Wait for controller, cainjector and webhook
6. Create a self-signed lab verification Certificate
```

---

## Check cert-manager status

```powershell
.\scripts\deployment-status.ps1 cert-manager
```

or:

```powershell
.\scripts\deployment-status.cmd cert-manager
```

Useful direct checks:

```powershell
vagrant ssh k3s-master -c "sudo kubectl -n cert-manager get pods"
```

```powershell
vagrant ssh k3s-master -c "sudo kubectl get certificate,certificaterequest,issuer,clusterissuer -A"
```

Expected cert-manager workloads include:

```text
cert-manager
cert-manager-cainjector
cert-manager-webhook
```

---

## cert-manager verification Certificate

The installer creates:

```text
Namespace:    cert-manager-test
Issuer:       selfsigned
Certificate:  lab-test-cert
Secret:       lab-test-tls
```

Check it:

```powershell
vagrant ssh k3s-master -c "sudo kubectl -n cert-manager-test get issuer,certificate,secret"
```

The Certificate should report:

```text
READY=True
```

The self-signed certificate is only a lab health check. It is not intended to
be used as a publicly trusted certificate.

---

## Remove cert-manager

Remove cert-manager while keeping its CRDs:

```powershell
.\scripts\remove-deployment.ps1 cert-manager
```

Remove cert-manager and its CRDs:

```powershell
.\scripts\remove-deployment.ps1 cert-manager -PurgePrerequisites
```

Be careful when deleting cert-manager CRDs in a cluster that already contains
real `Certificate`, `Issuer` or `ClusterIssuer` resources.

---

## Future HTTPS integration with Istio

The current Istio Stage 2 module provides HTTP ingress.

cert-manager is now available so the next deployment step can add HTTPS using:

```text
cert-manager
    |
    v
Certificate / Secret
    |
    v
Istio Gateway HTTPS listener
    |
    v
HTTPRoute
    |
    v
Application Service
```

A future TLS module can use a trusted CA or ACME issuer and reference the
generated Kubernetes TLS Secret from the Istio Gateway.

---

---

# Complete Stage 2 Deployment Order and Status

After the Istio and cert-manager deployment guidance above, use this section as
the **authoritative order for the complete Stage 2 platform**.

Install all Stage 2 components:

```powershell
.\scripts\deploy.ps1 all
```

The deployment order is:

```text
1. cert-manager
2. Longhorn
3. HashiCorp Vault
4. Monitoring
5. Argo CD
6. Istio + Gateway API + MetalLB
7. Velero + MinIO
```

Why this order:

```text
cert-manager
  certificate/controller foundation

Longhorn
  persistent storage foundation

Monitoring
  Prometheus + Alertmanager + Grafana

Argo CD
  GitOps platform

Istio + Gateway API + MetalLB
  creates the shared public-gateway and reconciles publishing for all
  browser-facing components already installed

Velero + MinIO
  backup platform; MinIO depends on Longhorn storage
```

When Istio is installed at step 6, the repository automatically runs the shared
publishing reconciliation so the already-installed Longhorn, Monitoring and
Argo CD services receive their `HTTPRoute` paths on `public-gateway`.

Check the complete Stage 2 platform:

```powershell
.\scripts\deployment-status.ps1 all
```

`deployment-status.ps1 all` includes **all deployments** in this order:

```text
1. cert-manager
   - cert-manager controller
   - cert-manager cainjector
   - cert-manager webhook
   - verification resources

2. Longhorn
   - Helm release
   - Longhorn pods
   - StorageClass
   - Longhorn nodes
   - Longhorn volumes

3. HashiCorp Vault
   - Vault Helm release
   - 3 Vault Raft server pods
   - Vault Agent Injector
   - 3 Longhorn-backed Vault PVCs
   - Vault services
   - initialized / sealed state for each Vault server

4. Monitoring
   - kube-prometheus-stack Helm release
   - Prometheus
   - Alertmanager
   - Grafana
   - monitoring services

5. Argo CD
   - Argo CD Helm release
   - Argo CD pods
   - services
   - Argo CD CRDs

6. Istio + Gateway API + MetalLB
   - Gateway API CRDs
   - Istio base / istiod
   - MetalLB controller / speakers
   - IPAddressPool / L2Advertisement
   - public-gateway
   - public-gateway-istio LoadBalancer
   - demo application / HTTPRoute

7. Velero + MinIO
   - Velero Helm release
   - Velero server
   - node-agent
   - BackupStorageLocation
   - MinIO
   - MinIO Longhorn PVC
   - existing Velero backups

8. Shared Gateway publishing
   - public-gateway address
   - all HTTPRoutes
   - final published URLs
```

The final publishing paths are:

```text
/demo
/longhorn
/vault
/grafana
/prometheus
/alertmanager
/argocd
/minio
```

So the normal complete verification command is only:

```powershell
.\scripts\deployment-status.ps1 all
```

Use individual status commands only when troubleshooting one component:

```powershell
.\scripts\deployment-status.ps1 cert-manager
.\scripts\deployment-status.ps1 longhorn
.\scripts\deployment-status.ps1 monitoring
.\scripts\deployment-status.ps1 argocd
.\scripts\deployment-status.ps1 istio
.\scripts\deployment-status.ps1 velero
```

# MetalLB Webhook Troubleshooting

MetalLB uses validating webhooks for its custom resources such as:

```text
IPAddressPool
L2Advertisement
```

The correct L2 configuration uses MetalLB CRs:

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: lan-pool
  namespace: metallb-system
spec:
  addresses:
    - 192.168.100.240-192.168.100.245
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: lan-l2
  namespace: metallb-system
spec:
  ipAddressPools:
    - lan-pool
```

If Kubernetes reports:

```text
failed calling webhook "ipaddresspoolvalidationwebhook.metallb.io"
context deadline exceeded
```

the CR syntax is not necessarily wrong. It means the Kubernetes API server
could not reach MetalLB's validating webhook in time.

For this local K3s/VirtualBox lab, the Stage 2 installer now:

1. installs MetalLB in L2-only mode;
2. disables FRR-K8s because BGP is not used;
3. pins the MetalLB controller/webhook to `k3s-master`;
4. waits for the webhook Service and endpoint;
5. tests webhook connectivity from `k3s-master`;
6. retries `IPAddressPool` and `L2Advertisement` creation.

Run the diagnostic command:

```powershell
.\scripts\metallb-webhook-check.ps1
```

Check manually:

```powershell
vagrant ssh k3s-master -c "sudo kubectl -n metallb-system get pods -o wide"
```

```powershell
vagrant ssh k3s-master -c "sudo kubectl -n metallb-system get svc,endpoints"
```

```powershell
vagrant ssh k3s-master -c "sudo kubectl get validatingwebhookconfiguration metallb-webhook-configuration"
```

After the webhook is healthy, rerun:

```powershell
.\scripts\deploy.ps1 istio
```

The deployment is idempotent. Existing Helm releases are upgraded/reused and
the MetalLB CRs are applied again.

---

# Istio Helm Profile Troubleshooting

If Stage 2 stops at the `istiod` step with:

```text
Error: execution error at (istiod/templates/zzz_profile.yaml:...):
unknown profile minimal
```

the base Istio chart and MetalLB installation are already usable. The problem is
only the `istiod` Helm value.

The repository installs the standard Istio control plane with:

```bash
helm upgrade --install istiod istio/istiod \
  --namespace istio-system \
  --version 1.31.0 \
  --wait \
  --timeout 5m
```

No `--set profile=minimal` is passed to the Helm chart.

Before changing the cluster, the installer also renders the chart as a
preflight validation:

```bash
helm template istiod istio/istiod \
  --namespace istio-system \
  --version 1.31.0
```

After updating the repository, you do **not** need to destroy or recreate the
K3s cluster, Gateway API CRDs, or MetalLB.

Simply run:

```powershell
. .\scripts\lab-config.ps1
.\scripts\deploy.ps1 istio
```

The deployment uses `helm upgrade --install` and `kubectl apply`, so the
already-created components are reused.

You can inspect the current releases first with:

```powershell
vagrant ssh k3s-master -c "sudo helm list -A"
```

After a successful rerun, verify:

```powershell
.\scripts\deployment-status.ps1 istio
```

The Kubernetes Gateway API `Gateway` uses:

```yaml
gatewayClassName: istio
```

Istio will automatically provision the associated gateway Deployment and
`LoadBalancer` Service. MetalLB then assigns that Service an address from the
configured LAN pool.

---

# Physical LAN CIDR

The current physical LAN used by this lab is:

```text
192.168.100.0/24
```

Current reserved addresses:

```text
K3s master LAN:   192.168.100.210
K3s worker1 LAN:  192.168.100.211
K3s worker2 LAN:  192.168.100.212

Remote K3s API:   https://192.168.100.210:6443

MetalLB pool:     192.168.100.240-192.168.100.245
```

The internal host-only K3s management network remains unchanged:

```text
192.168.56.0/24
```

---

# K3s Flannel Network Interface

This lab has three VM interfaces:

```text
eth0  VirtualBox NAT
      Used only for outbound internet/package downloads.
      Typical VM address: 10.0.2.15

eth1  VirtualBox host-only network
      Used for K3s node-to-node and Flannel VXLAN traffic.
      192.168.56.0/24

eth2  Bridged physical LAN
      Used for remote Kubernetes API access and MetalLB L2.
      192.168.100.0/24
```

Flannel must use:

```text
eth1
```

The local configuration contains:

```powershell
$env:K3S_FLANNEL_IFACE = "eth1"
```

Stage 1 passes this value to the K3s server and agents. Their K3s configuration
contains:

```yaml
flannel-iface: "eth1"
```

This is required because VirtualBox NAT commonly assigns `10.0.2.15` to
`eth0` inside every VM. If Flannel automatically selects `eth0`, VXLAN appears
similar to:

```text
vxlan id 1 local 10.0.2.15 dev eth0
```

and cross-node pod networking breaks. Typical symptoms include:

```text
CoreDNS timeouts from pods on worker nodes
lookup istiod.istio-system.svc: i/o timeout
Istio Gateway CrashLoopBackOff
MetalLB VIP allocated but not advertised
```

The correct result is:

```text
k3s-master:
  vxlan id 1 local 192.168.56.10 dev eth1

k3s-worker1:
  vxlan id 1 local 192.168.56.11 dev eth1

k3s-worker2:
  vxlan id 1 local 192.168.56.12 dev eth1
```

Verify at any time:

```powershell
.\scripts\check-flannel.ps1
```

For an existing cluster created before this fix, run:

```powershell
. .\scripts\lab-config.ps1
.\scripts\fix-flannel.ps1
```

The repair command:

```text
1. adds/updates flannel-iface: eth1 on all three nodes;
2. restarts k3s-agent on both workers;
3. restarts k3s on the master;
4. waits for all nodes to become Ready;
5. verifies flannel.1 on all nodes;
6. restarts CoreDNS;
7. restarts the Istio Gateway automatically if it already exists.
```

After repair:

```powershell
.\scripts\status.ps1
.\scripts\deployment-status.ps1 istio
```

Then verify the Istio Gateway/MetalLB VIP:

```powershell
curl http://192.168.100.240/
```

Use the actual Gateway `EXTERNAL-IP` if MetalLB allocated a different address
from `192.168.100.240-192.168.100.245`.

---

# Stage 2 Additional Platform Deployments

This section is appended to the existing README. The previous introduction,
architecture, networking, Stage 1, Istio, MetalLB, cert-manager, Flannel and
troubleshooting guidance above remains unchanged.

The next Stage 2 modules are:

```text
Longhorn
HashiCorp Vault
Monitoring
Argo CD
Velero + MinIO
```

Install all Stage 2 components in dependency-safe order:

```powershell
.\scripts\deploy.ps1 all
```

Order:

```text
1. cert-manager
2. Longhorn
3. HashiCorp Vault
4. Monitoring
5. Argo CD
6. Istio + Gateway API + MetalLB
7. Velero + MinIO
```

Check all:

```powershell
.\scripts\deployment-status.ps1 all
```

---

## Longhorn Deployment

Longhorn provides distributed persistent storage.

Pinned version:

```text
1.12.1
```

Install:

```powershell
.\scripts\deploy.ps1 longhorn
```

Status:

```powershell
.\scripts\deployment-status.ps1 longhorn
```

The module creates the default `longhorn` StorageClass with two replicas for
this three-node local lab.

Stage 1 already installs `open-iscsi` and `nfs-common` on all nodes.

UI:

```powershell
kubectl -n longhorn-system port-forward svc/longhorn-frontend 8081:80
```

Open:

```text
http://127.0.0.1:8081
```

---

## Monitoring Deployment

The monitoring module installs:

```text
kube-prometheus-stack 88.5.4
Prometheus
Alertmanager
Grafana
Prometheus Operator
kube-state-metrics
node-exporter
```

Install:

```powershell
.\scripts\deploy.ps1 monitoring
```

Status:

```powershell
.\scripts\deployment-status.ps1 monitoring
```

Lab settings:

```text
Prometheus retention: 2 days
Grafana persistence: disabled
K3s embedded control-plane scrape targets: disabled
```

Grafana:

```powershell
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
```

Open:

```text
http://127.0.0.1:3000
```

Login:

```text
admin / admin-lab
```

Prometheus:

```powershell
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090
```

Open:

```text
http://127.0.0.1:9090
```

---

## Argo CD Deployment

Argo CD provides GitOps continuous delivery.

Pinned Helm chart:

```text
10.4.0
```

Install:

```powershell
.\scripts\deploy.ps1 argocd
```

Status:

```powershell
.\scripts\deployment-status.ps1 argocd
```

UI:

```powershell
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

Open:

```text
https://127.0.0.1:8080
```

Username:

```text
admin
```

Retrieve initial password:

```powershell
vagrant ssh k3s-master -c "sudo kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
```

---

## Velero + MinIO Deployment

Velero provides Kubernetes backup and restore.

Pinned:

```text
Velero Helm chart: 12.1.0
Velero app:        1.18.1
AWS plugin:        v1.14.2
```

For this lab, MinIO provides S3-compatible object storage.

MinIO storage:

```text
Namespace:    velero
PVC:          minio-data
StorageClass: longhorn
Size:         10Gi
Bucket:       velero
```

Longhorn is therefore required first:

```powershell
.\scripts\deploy.ps1 longhorn
.\scripts\deploy.ps1 velero
```

Or:

```powershell
.\scripts\deploy.ps1 all
```

Status:

```powershell
.\scripts\deployment-status.ps1 velero
```

Create a restore point:

```powershell
.\scripts\cluster-points.ps1 create before-change
```

List:

```powershell
.\scripts\cluster-points.ps1 list
```

Restore:

```powershell
.\scripts\cluster-points.ps1 restore before-change
```

The backup helper excludes the `velero` namespace so MinIO does not back up its
own backup store.

MinIO console:

```powershell
kubectl -n velero port-forward svc/minio 9001:9001
```

Open:

```text
http://127.0.0.1:9001
```

Lab login:

```text
minio / minio123
```

### Important backup limitation

MinIO is inside the Kubernetes lab and its data is stored on Longhorn.

Velero backups can restore Kubernetes resources and persistent data while the
lab exists, but a complete VM/lab destroy also removes Longhorn and MinIO.

For backups that must survive a complete destroy, configure Velero to use
external S3-compatible object storage.

---

## Expected Additional Namespaces

After deploying all modules:

```powershell
kubectl get pods -A
```

you should have namespaces similar to:

```text
argocd
cert-manager
demo
istio-ingress
istio-system
kube-system
longhorn-system
metallb-system
monitoring
velero
```

The full Stage 2 platform is:

```text
K3s
|
+-- Flannel / CoreDNS
|
+-- Longhorn
|   +-- persistent storage
|
+-- cert-manager
|
+-- Gateway API
|   +-- MetalLB
|   +-- Istio
|
+-- Monitoring
|   +-- Prometheus
|   +-- Alertmanager
|   +-- Grafana
|
+-- Argo CD
|   +-- GitOps
|
+-- Velero
    +-- node-agent filesystem backup
    +-- MinIO
        +-- Longhorn PVC
```

---

# Shared Default Gateway Publishing

This section is appended to the existing README. All previous cluster,
architecture, networking, Flannel, Istio, MetalLB, cert-manager, Longhorn,
monitoring, Argo CD and Velero guidance above remains unchanged.

## Publishing design

The lab uses **one default Istio Gateway for all HTTP publishing**:

```text
Gateway namespace: istio-ingress
Gateway name:      public-gateway
GatewayClass:      istio
Listener:          http / port 80
MetalLB address:   192.168.100.240-192.168.100.245
```

The normal environment configuration includes:

```powershell
$env:K8S_GATEWAY_NAMESPACE = "istio-ingress"
$env:K8S_GATEWAY_NAME      = "public-gateway"
```

All application/platform routes attach to this same Gateway with
`HTTPRoute.parentRefs`.

Istio supports attaching HTTPRoutes from other namespaces when the Gateway
listener permits them. The repository's `public-gateway` listener uses:

```yaml
allowedRoutes:
  namespaces:
    from: All
```

## Published path map

After Stage 2 deployment, use:

```powershell
.\scripts\publishing-status.ps1
```

The shared path map is:

| Path | Namespace | Backend |
|---|---|---|
| `/demo` | `demo` | demo hello service |
| `/longhorn` | `longhorn-system` | Longhorn UI |
| `/grafana` | `monitoring` | Grafana |
| `/prometheus` | `monitoring` | Prometheus |
| `/alertmanager` | `monitoring` | Alertmanager |
| `/argocd` | `argocd` | Argo CD server/UI |
| `/minio` | `velero` | MinIO Console |

If MetalLB assigns `192.168.100.240`, the URLs are:

```text
http://192.168.100.240/demo
http://192.168.100.240/longhorn
http://192.168.100.240/grafana
http://192.168.100.240/prometheus
http://192.168.100.240/alertmanager
http://192.168.100.240/argocd
http://192.168.100.240/minio
```

Always use the actual Gateway address shown by:

```powershell
kubectl -n istio-ingress get gateway public-gateway
```

or:

```powershell
.\scripts\publishing-status.ps1
```

## Publish/reconcile all installed services

```powershell
. .\scripts\lab-config.ps1
.\scripts\publish.ps1 all
```

The command is safe to rerun. It:

```text
1. verifies public-gateway is Programmed;
2. discovers the actual Gateway IP;
3. creates/reconciles HTTPRoutes;
4. configures Grafana for /grafana;
5. configures Prometheus for /prometheus;
6. configures Alertmanager for /alertmanager;
7. configures Argo CD for /argocd;
8. configures MinIO Console for /minio.
```

Individual publishing is also supported:

```powershell
.\scripts\publish.ps1 longhorn
.\scripts\publish.ps1 vault
.\scripts\publish.ps1 monitoring
.\scripts\publish.ps1 argocd
.\scripts\publish.ps1 velero
```

Remove only the HTTPRoutes while keeping workloads and the Gateway:

```powershell
.\scripts\unpublish.ps1
```

## Deployment behavior

`deploy.ps1 all` uses the repository's authoritative Stage 2 order:

```text
1. cert-manager
2. Longhorn
3. HashiCorp Vault
4. Monitoring
5. Argo CD
6. Istio + Gateway API + MetalLB
7. Velero + MinIO
```

Browser-facing components installed before Istio are initially installed
without public routes. When Istio is installed at step 6, the repository runs
`publish.ps1 all`, which attaches all already-installed browser services to the
shared `public-gateway`. Velero/MinIO is installed last and is published after
its deployment completes.

## Why some components do not have a path

### cert-manager

cert-manager is a Kubernetes controller/CRD platform. It does not provide a
browser UI, so there is no `/cert-manager` HTTP endpoint to publish.

Use:

```powershell
kubectl get certificate,issuer,clusterissuer -A
```

### Velero

Velero itself is primarily operated through Kubernetes CRDs and the `velero`
CLI. The repository publishes the **MinIO Console** at `/minio`, because MinIO
is the browser interface for the lab's Velero object-storage backup target.

## MinIO S3 API

Only the MinIO **Console** is published under `/minio`.

The MinIO S3 API on port `9000` is intentionally not published as
`/s3` or another URL prefix. S3 AWS Signature V4 calculations do not support
arbitrary reverse-proxy path prefixes reliably. Keep the S3 endpoint internal
for Velero, or use a dedicated hostname if external S3 API access is required.

## Longhorn security note

The Longhorn Helm installation does not enable authentication on the UI by
default. `/longhorn` should therefore be considered a **trusted-lab-LAN**
endpoint and should not be exposed directly to an untrusted/public network.

## Future HTTPS

The shared publishing model is ready for a later HTTPS listener:

```text
cert-manager
     |
     v
TLS Secret
     |
     v
public-gateway :443
     |
     +-- /demo
     +-- /longhorn
     +-- /grafana
     +-- /prometheus
     +-- /alertmanager
     +-- /argocd
     +-- /minio
```

The same HTTPRoutes can continue using the same `public-gateway`; only the
Gateway listener/certificate configuration needs to be extended.

---

# Longhorn and MinIO White Page Fix

If these URLs return HTML but show a blank/white browser page:

```text
http://<gateway-ip>/longhorn
http://<gateway-ip>/minio
```

the shared Gateway route must preserve the public subpath for the browser while
removing that prefix before forwarding to the backend UI service.

The repository now treats these as canonical URLs:

```text
http://<gateway-ip>/longhorn/
http://<gateway-ip>/minio/
```

The Gateway behavior is:

```text
/longhorn
    |
    +-- HTTP 302 --> /longhorn/
                       |
                       +-- browser requests /longhorn/<asset>
                       |
                       +-- Gateway strips /longhorn/
                       |
                       +-- longhorn-frontend receives /<asset>

/minio
    |
    +-- HTTP 302 --> /minio/
                       |
                       +-- browser requests /minio/<asset>
                       |
                       +-- Gateway strips /minio/
                       |
                       +-- MinIO Console receives /<asset>
```

For MinIO the publishing reconciler also sets:

```text
MINIO_BROWSER_REDIRECT_URL=http://<gateway-ip>/minio/
```

Reconcile the corrected routes:

```powershell
. .\scripts\lab-config.ps1
.\scripts\publish.ps1 longhorn
.\scripts\publish.ps1 velero
```

Or reconcile everything:

```powershell
.\scripts\publish.ps1 all
```

Then verify:

```powershell
.\scripts\publishing-status.ps1
```

Use:

```text
http://192.168.100.240/longhorn/
http://192.168.100.240/minio/
```

when `192.168.100.240` is the current `public-gateway` address.

If a browser cached the previous broken SPA response, perform one hard refresh
after reconciling the routes.

---

# Longhorn Publishing Correction — Host-Based Route

The Longhorn browser error:

```text
runtime~main....js  Uncaught SyntaxError: Unexpected token '<'
styles....js        Uncaught SyntaxError: Unexpected token '<'
main....js          Uncaught SyntaxError: Unexpected token '<'
```

means the browser requested JavaScript but received HTML.

Longhorn's UI generates root-level requests such as:

```text
/runtime~main....js
/styles....js
/main....js
/v1/...
```

When the page is mounted at `/longhorn/`, those requests no longer include the
`/longhorn` prefix. A normal Gateway API prefix rewrite cannot rewrite the HTML
or JavaScript generated by the application, so a pure Longhorn subpath is not
reliable.

## Correct design

Longhorn still uses the same shared Gateway:

```text
istio-ingress/public-gateway
```

The `/longhorn` path is retained as an entry URL, but it redirects to a
host-based route on the same Gateway.

With Gateway IP `192.168.100.240`:

```text
http://192.168.100.240/longhorn
        |
        | HTTP 302
        v
http://longhorn.192-168-100-240.nip.io/
        |
        v
istio-ingress/public-gateway
        |
        v
longhorn-system/longhorn-frontend:80
```

The repository derives the hostname from the actual Gateway IP using `nip.io`.

Apply:

```powershell
. .\scripts\lab-config.ps1
.\scripts\publish.ps1 longhorn
```

Check:

```powershell
.\scripts\publishing-status.ps1
```

Then open:

```text
http://192.168.100.240/longhorn
```

or directly:

```text
http://longhorn.192-168-100-240.nip.io/
```

If you prefer your own DNS instead of `nip.io`:

```powershell
$env:LONGHORN_PUBLISH_HOST = "longhorn.lab.local"
.\scripts\publish.ps1 longhorn
```

and configure `longhorn.lab.local` to resolve to the Gateway IP.

All other compatible routes remain on the same shared Gateway:

```text
/demo
/grafana
/prometheus
/alertmanager
/argocd
/minio/
```

---

# Longhorn Route Reconciliation Validation

If status shows:

```text
longhorn        http:///
```

the live `longhorn-ui` object still has no hostname.

The Longhorn publisher now deletes the previous `longhorn-entry` and
`longhorn-ui` routes before applying the generated host-based routes, then reads
the live route back from Kubernetes and fails unless:

```yaml
spec:
  hostnames:
    - longhorn.<gateway-ip-with-dashes>.nip.io
```

matches the generated hostname exactly.

For Gateway IP `192.168.100.240`, reconciliation must produce:

```text
Hostname: longhorn.192-168-100-240.nip.io
```

Apply:

```powershell
. .\scripts\lab-config.ps1
.\scripts\publish.ps1 longhorn
```

Then validate the actual live object:

```powershell
.\scripts\longhorn-publishing-check.ps1
```

Finally:

```powershell
.\scripts\publishing-status.ps1
```

The status command now reports an explicit error if the hostname is empty
instead of silently printing `http:///`.

---

# HashiCorp Vault — HA Raft with Longhorn Persistence

HashiCorp Vault is now part of Stage 2 and is installed **after Longhorn**
because Vault's integrated Raft storage uses Longhorn-backed PVCs.

Pinned versions:

```text
Vault Helm chart: 0.34.1
Vault app:        2.0.4
```

The lab deployment is:

```text
vault namespace
|
+-- vault-0
|   +-- data-vault-0 PVC -> longhorn -> 5Gi
|
+-- vault-1
|   +-- data-vault-1 PVC -> longhorn -> 5Gi
|
+-- vault-2
|   +-- data-vault-2 PVC -> longhorn -> 5Gi
|
+-- Integrated Storage (Raft)
|
+-- vault-agent-injector
|
+-- vault-ui ClusterIP service
```

This is not Vault dev mode. Vault data persists across pod and VM restarts as
long as the Longhorn volumes remain available.

## Updated complete Stage 2 order

```text
1. cert-manager
2. Longhorn
3. HashiCorp Vault
4. Monitoring
5. Argo CD
6. Istio + Gateway API + MetalLB
7. Velero + MinIO
8. Shared Gateway publishing status
```

Install everything:

```powershell
.\scripts\deploy.ps1 all
```

Or install Vault independently after Longhorn:

```powershell
. .\scripts\lab-config.ps1

.\scripts\deploy.ps1 longhorn
.\scripts\deploy.ps1 vault
```

## Vault initialization

A new persistent Vault cluster starts **uninitialized and sealed**. This is
expected.

Initialize the first Vault pod, form the three-node Raft cluster and unseal all
three nodes:

```powershell
.\scripts\vault-init.ps1
```

The script creates one Shamir unseal key/share for this local lab and prints:

```text
Unseal Key
Root Token
```

Save both securely outside this Git repository.

**Never commit the Vault root token or unseal key to Git.**

After initialization, verify:

```powershell
.\scripts\deployment-status.ps1 vault
```

## Unseal after restart

The Longhorn PVCs preserve Vault data, but Shamir-sealed Vault servers must be
unsealed again after they restart.

Run:

```powershell
.\scripts\vault-unseal.ps1
```

The script securely prompts for the unseal key and unseals:

```text
vault-0
vault-1
vault-2
```

## Vault PVC verification

Check the Vault PVCs:

```powershell
vagrant ssh k3s-master -c "sudo kubectl -n vault get pvc -o wide"
```

Expected:

```text
3 PVCs
STATUS:       Bound
STORAGECLASS: longhorn
SIZE:         5Gi each
```

Check the underlying PVs:

```powershell
vagrant ssh k3s-master -c "sudo kubectl get pv"
```

Check Vault and Longhorn together:

```powershell
vagrant ssh k3s-master -c "sudo kubectl -n vault get pods,pvc"
vagrant ssh k3s-master -c "sudo kubectl -n longhorn-system get volumes.longhorn.io"
```

## Vault publishing

Vault uses the same:

```text
istio-ingress/public-gateway
```

as the other Stage 2 services.

The Vault UI does not reliably support a non-root browser base path, so
`/vault` is kept as an entry URL and redirects to a Vault hostname on the same
Gateway.

With Gateway IP `192.168.100.240`:

```text
http://192.168.100.240/vault
        |
        | HTTP 302
        v
http://vault.192-168-100-240.nip.io/
        |
        v
same istio-ingress/public-gateway
        |
        v
vault/vault-ui:8200
```

Publish/reconcile Vault:

```powershell
.\scripts\publish.ps1 vault
```

Check all publishing:

```powershell
.\scripts\publishing-status.ps1
```

Expected Vault entries:

```text
vault-entry     http://192.168.100.240/vault
vault           http://vault.192-168-100-240.nip.io/
```

To use your own DNS instead of `nip.io`:

```powershell
$env:VAULT_PUBLISH_HOST = "vault.lab.local"
.\scripts\publish.ps1 vault
```

Then make `vault.lab.local` resolve to the current Gateway IP.

## Vault Agent Injector

The official Vault Agent Injector is enabled in this deployment. This prepares
the lab for Kubernetes workloads that need Vault-backed secrets.

The repository does not automatically create application policies, Kubernetes
auth roles or secret engines because those should be defined per application
and namespace.

## Vault status in the complete status command

The normal command:

```powershell
.\scripts\deployment-status.ps1 all
```

now checks:

```text
1. cert-manager
2. Longhorn
3. HashiCorp Vault
4. Monitoring
5. Argo CD
6. Istio + Gateway API + MetalLB
7. Velero + MinIO
8. Shared Gateway publishing / HTTPRoutes
```

For Vault it reports:

```text
Helm release
StatefulSet
Vault Agent Injector
vault-0 / vault-1 / vault-2
PVCs and StorageClass
Vault services
Initialized / Sealed state
```

## Vault removal protection

Vault PVCs contain the Vault Raft database. Removal is therefore protected.

This command refuses to remove Vault while the persistent PVCs exist:

```powershell
.\scripts\remove-deployment.ps1 vault
```

To intentionally remove Vault **and its persistent data**:

```powershell
.\scripts\remove-deployment.ps1 vault -Force
```

Use `-Force` only when losing the Vault data is intentional.

## TLS note

This lab currently uses HTTP internally for Vault to match the existing
development Gateway model.

For a production-style deployment, the next step should be to use
cert-manager/trusted certificates and publish Vault over HTTPS before storing
real production secrets.

---

# Vault UI Before Initialization

Vault is configured so its UI can be reached **before initialization or
unseal**.

The Helm values use:

```yaml
ui:
  enabled: true
  serviceType: ClusterIP
  publishNotReadyAddresses: true
  activeVaultPodOnly: false
  externalPort: 8200
  targetPort: 8200
```

This prevents the previous:

```text
no healthy upstream
```

condition.

The reason is:

```text
publishNotReadyAddresses: true
  -> sealed/uninitialized Vault pods remain in the UI Service endpoints

activeVaultPodOnly: false
  -> the UI Service does not require vault-active=true
  -> before initialization there is no HA leader yet
```

The HA Raft and persistent-storage design is unchanged:

```text
vault-0 -> 5Gi Longhorn PVC
vault-1 -> 5Gi Longhorn PVC
vault-2 -> 5Gi Longhorn PVC
```

## Flow

Deploy:

```powershell
. .\scripts\lab-config.ps1
.\scripts\deploy.ps1 vault
```

Publish:

```powershell
.\scripts\publish.ps1 vault
```

Check:

```powershell
.\scripts\deployment-status.ps1 vault
.\scripts\publishing-status.ps1
```

Open:

```text
http://192.168.100.240/vault
```

which redirects to:

```text
http://vault.192-168-100-240.nip.io/
```

At this point the UI is reachable even if Vault is still:

```text
Initialized: false
Sealed:      true
```

Then initialize the complete three-node Raft cluster:

```powershell
.\scripts\vault-init.ps1
```

After a future restart, Longhorn keeps the Raft data, but Shamir-sealed Vault
servers must be unsealed again:

```powershell
.\scripts\vault-unseal.ps1
```

To verify the UI Service has endpoints before initialization:

```powershell
vagrant ssh k3s-master -c "sudo kubectl -n vault get endpointslice -l kubernetes.io/service-name=vault-ui -o wide"
```
