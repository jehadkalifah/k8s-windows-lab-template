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
