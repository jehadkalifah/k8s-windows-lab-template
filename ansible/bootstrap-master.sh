#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y curl jq ca-certificates git python3 python3-pip

hostnamectl set-hostname k3s-master

cat >/etc/hosts <<'EOF'
127.0.0.1 localhost
192.168.56.10 k3s-master
192.168.56.11 k3s-worker1
192.168.56.12 k3s-worker2
EOF

if ! systemctl is-active --quiet k3s; then
  curl -sfL https://get.k3s.io | \
    INSTALL_K3S_VERSION=v1.36.1+k3s1 \
    INSTALL_K3S_EXEC="server --disable=traefik --disable=servicelb --disable=local-storage" \
    sh -
fi

mkdir -p /vagrant/.bootstrap
cat /var/lib/rancher/k3s/server/node-token >/vagrant/.k3s-token
chmod 600 /vagrant/.k3s-token

# Install Ansible inside the master so the host does not need Ansible.
python3 -m pip install --break-system-packages ansible-core==2.19.1
