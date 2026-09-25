#!/usr/bin/env bash
set -euo pipefail

SYS_CLASS_BLOCK_ROOT="${SYS_CLASS_BLOCK_ROOT:-/sys/class/block}"

resolve_backing_partition_device() {
  local current_device_name next_device_name

  current_device_name="$(basename "$(readlink -f "$1")")"
  while [ ! -f "${SYS_CLASS_BLOCK_ROOT}/${current_device_name}/partition" ] && [ -d "${SYS_CLASS_BLOCK_ROOT}/${current_device_name}/slaves" ]; do
    next_device_name="$(find "${SYS_CLASS_BLOCK_ROOT}/${current_device_name}/slaves" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | head -1 || true)"
    if [ -z "${next_device_name}" ]; then
      break
    fi

    current_device_name="${next_device_name}"
  done

  if [ ! -f "${SYS_CLASS_BLOCK_ROOT}/${current_device_name}/partition" ]; then
    return 1
  fi

  printf '/dev/%s\n' "${current_device_name}"
}

grow_root_filesystem() {
  local root_source root_fs partition_device partition_device_name partition_number parent_disk_name parent_disk_device
  local growpart_output=""
  local growpart_status=0
  local -a required_packages=()

  root_source="$(findmnt -n -o SOURCE / || true)"
  root_fs="$(findmnt -n -o FSTYPE / || true)"
  if [ -z "${root_source}" ] || [ -z "${root_fs}" ]; then
    echo "Skipping root disk growth: unable to determine the root filesystem."
    return 0
  fi

  if ! partition_device="$(resolve_backing_partition_device "${root_source}")"; then
    echo "Skipping root disk growth: unsupported root device layout (${root_source:-unknown})."
    return 0
  fi
  partition_device_name="$(basename "${partition_device}")"
  parent_disk_name="$(basename "$(readlink -f "${SYS_CLASS_BLOCK_ROOT}/${partition_device_name}/..")")"
  partition_number="$(cat "${SYS_CLASS_BLOCK_ROOT}/${partition_device_name}/partition" 2>/dev/null || true)"

  if [ -z "${partition_device}" ] || [ -z "${parent_disk_name}" ] || [ -z "${partition_number}" ]; then
    echo "Skipping root disk growth: unsupported root device layout (${root_source:-unknown})."
    return 0
  fi

  parent_disk_device="/dev/${parent_disk_name}"

  if ! command -v growpart >/dev/null 2>&1; then
    required_packages+=(cloud-guest-utils)
  fi
  if [[ "${root_fs}" =~ ^ext[234]$ ]] && ! command -v resize2fs >/dev/null 2>&1; then
    required_packages+=(e2fsprogs)
  fi
  if [ "${root_fs}" = "xfs" ] && ! command -v xfs_growfs >/dev/null 2>&1; then
    required_packages+=(xfsprogs)
  fi
  if [ "${#required_packages[@]}" -gt 0 ]; then
    if ! command -v apt-get >/dev/null 2>&1; then
      echo "Skipping automatic installation of root disk growth tools because apt-get is unavailable."
      return 0
    fi

    if [ "${ROOT_GROW_SKIP_APT_UPDATE:-0}" != "1" ]; then
      apt-get update
    fi
    apt-get install -y "${required_packages[@]}"
  fi

  set +e
  growpart_output="$(growpart "${parent_disk_device}" "${partition_number}" 2>&1)"
  growpart_status=$?
  set -e
  printf '%s\n' "${growpart_output}"

  if [ "${growpart_status}" -ne 0 ]; then
    return "${growpart_status}"
  fi

  case "${root_fs}" in
    ext2|ext3|ext4)
      resize2fs "${root_source}"
      ;;
    xfs)
      set +e
      growpart_output="$(xfs_growfs / 2>&1)"
      growpart_status=$?
      set -e
      printf '%s\n' "${growpart_output}"
      if [ "${growpart_status}" -ne 0 ] && ! printf '%s\n' "${growpart_output}" | grep -Eiq 'data size unchanged|nothing to do'; then
        return "${growpart_status}"
      fi
      ;;
    *)
      echo "Skipping filesystem growth for unsupported root filesystem type: ${root_fs}."
      ;;
  esac
}
