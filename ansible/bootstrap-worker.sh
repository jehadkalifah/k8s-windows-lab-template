#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

grow_root_filesystem() {
  local root_source root_fs partition_device partition_number parent_disk_name parent_disk_device
  local growpart_output=""
  local growpart_status=0

  root_source="$(findmnt -n -o SOURCE / || true)"
  root_fs="$(findmnt -n -o FSTYPE / || true)"
  if [ -z "${root_source}" ] || [ -z "${root_fs}" ]; then
    echo "Skipping root disk growth: unable to determine the root filesystem."
    return 0
  fi
  partition_device="$(readlink -f "${root_source}")"
  parent_disk_name="$(lsblk -no PKNAME "${partition_device}" 2>/dev/null | head -1 || true)"
  partition_number="$(lsblk -no PARTN "${partition_device}" 2>/dev/null | head -1 || true)"

  if [ -z "${partition_device}" ] || [ -z "${parent_disk_name}" ] || [ -z "${partition_number}" ]; then
    echo "Skipping root disk growth: unsupported root device layout (${root_source:-unknown})."
    return 0
  fi

  parent_disk_device="/dev/${parent_disk_name}"

  if ! command -v growpart >/dev/null 2>&1; then
    apt-get update
    apt-get install -y cloud-guest-utils
  fi

  if [ "${root_fs}" = "xfs" ] && ! command -v xfs_growfs >/dev/null 2>&1; then
    apt-get update
    apt-get install -y xfsprogs
  fi

  set +e
  growpart_output="$(growpart "${parent_disk_device}" "${partition_number}" 2>&1)"
  growpart_status=$?
  set -e
  printf '%s\n' "${growpart_output}"

  if [ "${growpart_status}" -ne 0 ] && ! printf '%s\n' "${growpart_output}" | grep -Eiq 'NOCHANGE|nothing to do'; then
    return "${growpart_status}"
  fi

  case "${root_fs}" in
    ext2|ext3|ext4)
      resize2fs "${partition_device}"
      ;;
    xfs)
      xfs_growfs /
      ;;
    *)
      echo "Skipping filesystem growth for unsupported root filesystem type: ${root_fs}."
      ;;
  esac
}

grow_root_filesystem

apt-get update
apt-get install -y \
  curl \
  jq \
  ca-certificates \
  git \
  unzip \
  open-iscsi \
  nfs-common \
  cryptsetup \
  dmsetup

systemctl enable --now iscsid || true
systemctl enable --now open-iscsi || true

cat >/etc/hosts <<'EOF'
127.0.0.1 localhost
192.168.56.10 k3s-master
192.168.56.11 k3s-worker1
192.168.56.12 k3s-worker2
EOF
