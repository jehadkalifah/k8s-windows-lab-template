# Remote Kubernetes API Access

The K3s control plane uses the stable host-only address `192.168.56.10`
internally and also exposes its API on the master's physical-LAN address:

```text
https://192.168.10.210:6443
```

The K3s API certificate contains `192.168.10.210` as a TLS SAN.

## LAN addresses

```text
k3s-master:  192.168.10.210
k3s-worker1: 192.168.10.211
k3s-worker2: 192.168.10.212

MetalLB:     192.168.10.240-192.168.10.245
```

## Before using direct Vagrant commands

```powershell
. .\scripts\lab-config.ps1
```

## Test the API

```powershell
Test-NetConnection 192.168.10.210 -Port 6443
```

## Kubeconfig

The host generates:

```text
.kube\remote-kubeconfig.yaml
```

Copy that file to a trusted remote machine and set:

```powershell
$env:KUBECONFIG="$HOME\.kube\k3s-lab.yaml"
kubectl get nodes
```

Do not use a MetalLB service IP as the Kubernetes API endpoint. MetalLB is
for application LoadBalancer services; Kubernetes administrative API traffic
uses the master's bridged LAN IP.
