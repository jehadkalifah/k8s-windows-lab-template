#!/usr/bin/env bash
set -euo pipefail

MGMT_IP="${1:-192.168.56.10}"
API_LAN_IP="${2:-}"
K3S_VERSION="v1.36.1+k3s1"

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y \
  curl \
  jq \
  ca-certificates \
  git \
  unzip \
  python3 \
  python3-pip \
  open-iscsi \
  nfs-common \
  cryptsetup \
  dmsetup

systemctl enable --now iscsid || true
systemctl enable --now open-iscsi || true

hostnamectl set-hostname k3s-master

cat >/etc/hosts <<'EOF'
127.0.0.1 localhost
192.168.56.10 k3s-master
192.168.56.11 k3s-worker1
192.168.56.12 k3s-worker2
EOF

mkdir -p /etc/rancher/k3s
cat >/etc/rancher/k3s/config.yaml <<EOF
node-ip: "${MGMT_IP}"
advertise-address: "${MGMT_IP}"
write-kubeconfig-mode: "0600"
disable:
  - traefik
  - servicelb
  - local-storage
tls-san:
  - "${MGMT_IP}"
EOF

if [ -n "${API_LAN_IP}" ]; then
  cat >>/etc/rancher/k3s/config.yaml <<EOF
  - "${API_LAN_IP}"
EOF
fi

if ! systemctl is-active --quiet k3s; then
  curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${K3S_VERSION}" sh -
else
  systemctl restart k3s
fi

# Wait for the server token and API before workers are provisioned.
for i in $(seq 1 60); do
  if [ -s /var/lib/rancher/k3s/server/node-token ] && \
     KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl get --raw=/readyz >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

if [ ! -s /var/lib/rancher/k3s/server/node-token ]; then
  echo "K3s server token was not created." >&2
  exit 1
fi

cat /var/lib/rancher/k3s/server/node-token >/vagrant/.k3s-token
chmod 600 /vagrant/.k3s-token

# Ansible runs locally on this master. It never SSHes to the Vagrant VMs.
python3 -m pip install --break-system-packages 'ansible-core==2.19.1'
