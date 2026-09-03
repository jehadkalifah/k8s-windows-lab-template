# Fixed Issues

## Ansible SSH private-key issue

The old deployment playbook attempted to SSH from inside the master using
host-side Vagrant private-key paths. That design is no longer used.

## Stage separation

`up.ps1` now creates the K3s cluster only.

All platform/application deployment is Stage 2.

## Istio 1.31 Helm repository

Istio 1.31 uses:

```text
https://blob.istio.io/istio-release/charts
```

instead of the old GCP Helm repository.


## Flannel selected VirtualBox NAT instead of the inter-node NIC

VirtualBox gives every VM a NAT interface on `eth0`, commonly with
`10.0.2.15`. K3s automatic interface selection caused Flannel VXLAN to bind to
that NAT NIC:

```text
vxlan id 1 local 10.0.2.15 dev eth0
```

Because each VM had the same NAT-side address, cross-node pod traffic and
cluster DNS failed.

The repository now explicitly configures:

```yaml
flannel-iface: eth1
```

where `eth1` is the stable host-only `192.168.56.0/24` network used for K3s
inter-node traffic.
