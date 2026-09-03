#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y curl jq ca-certificates open-iscsi nfs-common cryptsetup dmsetup

systemctl enable --now iscsid || true
systemctl enable --now open-iscsi || true

cat >/etc/hosts <<'EOF'
127.0.0.1 localhost
192.168.56.10 k3s-master
192.168.56.11 k3s-worker1
192.168.56.12 k3s-worker2
EOF
