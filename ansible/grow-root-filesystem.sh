#!/usr/bin/env bash
set -euo pipefail

SYS_CLASS_BLOCK_ROOT="${SYS_CLASS_BLOCK_ROOT:-/sys/class/block}"

resolve_block_device_name() {
  local device_path="$1"
  local device_name=""
  local vg_name=""
  local lv_name=""
  local mapper_name=""
  local candidate_path candidate_name

  device_name="${device_path##*/}"
  if [ -e "${SYS_CLASS_BLOCK_ROOT}/${device_name}" ]; then
    printf '%s\n' "${device_name}"
    return 0
  fi

  if [[ "${device_path}" == /dev/mapper/* ]]; then
    for candidate_path in "${SYS_CLASS_BLOCK_ROOT}"/dm-*; do
      [ -d "${candidate_path}/dm" ] || continue
      candidate_name="$(cat "${candidate_path}/dm/name" 2>/dev/null || true)"
      if [ "${candidate_name}" = "${device_name}" ]; then
        printf '%s\n' "${candidate_path##*/}"
        return 0
      fi
    done
  elif [[ "${device_path}" == /dev/*/* ]]; then
    vg_name="${device_path#/dev/}"
    vg_name="${vg_name%%/*}"
    lv_name="${device_path##*/}"
    mapper_name="${vg_name//-/--}-${lv_name//-/--}"
    for candidate_path in "${SYS_CLASS_BLOCK_ROOT}"/dm-*; do
      [ -d "${candidate_path}/dm" ] || continue
      candidate_name="$(cat "${candidate_path}/dm/name" 2>/dev/null || true)"
      if [ "${candidate_name}" = "${mapper_name}" ]; then
        printf '%s\n' "${candidate_path##*/}"
        return 0
      fi
    done
  fi

  printf '%s\n' "${device_name}"
}

resolve_parent_disk_name() {
  local partition_device_name="$1"
  local parent_disk_path=""
  local had_errexit=0

  case $- in
    *e*)
      had_errexit=1
      set +e
      ;;
  esac
  parent_disk_path="$(
    cd -P "${SYS_CLASS_BLOCK_ROOT}/${partition_device_name}" 2>/dev/null &&
    cd -P .. 2>/dev/null &&
    pwd -P
  )"
  if [ "${had_errexit}" -eq 1 ]; then
    set -e
  fi
  if [ -z "${parent_disk_path}" ]; then
    return 1
  fi

  printf '%s\n' "${parent_disk_path##*/}"
}

resolve_backing_partition_device() {
  local current_device_name next_device_name

  current_device_name="$(resolve_block_device_name "$1")"
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

is_lvm_root_source() {
  local root_source="$1"
  local root_device_name dm_uuid_path dm_uuid=""

  root_device_name="$(resolve_block_device_name "${root_source}")"
  dm_uuid_path="${SYS_CLASS_BLOCK_ROOT}/${root_device_name}/dm/uuid"
  if [ -f "${dm_uuid_path}" ]; then
    dm_uuid="$(cat "${dm_uuid_path}" 2>/dev/null || true)"
    if [[ "${dm_uuid}" == LVM-* ]]; then
      return 0
    fi
  fi

  return 1
}

read_lvm_value() {
  local value=""
  local had_errexit=0
  local command_status=0

  case $- in
    *e*)
      had_errexit=1
      set +e
      ;;
  esac
  value="$("$@" 2>/dev/null)"
  command_status=$?
  if [ "${had_errexit}" -eq 1 ]; then
    set -e
  fi
  value="${value//[[:space:]]/}"
  printf '%s\n' "${value}"
  return "${command_status}"
}

resolve_lvm_logical_volume_path() {
  local root_source="$1"
  local raw_output=""
  local lv_path=""
  local line=""
  local lv_path_count=0
  local root_device_name=""
  local command_status=0
  local had_errexit=0

  if [[ "${root_source}" == /dev/*/* ]] && [[ "${root_source}" != /dev/mapper/* ]]; then
    root_device_name="$(resolve_block_device_name "${root_source}")"
    if [[ "${root_device_name}" == dm-* ]]; then
      printf '%s\n' "${root_source}"
      return 0
    fi
  fi

  case $- in
    *e*)
      had_errexit=1
      set +e
      ;;
  esac
  raw_output="$(lvs --noheadings -o vg_name,lv_name --separator / "${root_source}" 2>/dev/null)"
  command_status=$?
  if [ "${had_errexit}" -eq 1 ]; then
    set -e
  fi
  while IFS= read -r line; do
    line="${line//[[:space:]]/}"
    if [ -n "${line}" ]; then
      lv_path="${line}"
      lv_path_count=$((lv_path_count + 1))
    fi
  done <<<"${raw_output}"
  if [ "${command_status}" -eq 0 ] && [ "${lv_path_count}" -eq 1 ] && [ -n "${lv_path}" ]; then
    printf '/dev/%s\n' "${lv_path}"
    return 0
  fi

  if [ "${command_status}" -eq 0 ]; then
    return 1
  fi

  return "${command_status}"
}

read_block_device_size_bytes() {
  local device_name="$1"
  local size_in_sectors=""

  # Linux exposes /sys/class/block/*/size in 512-byte units regardless of the
  # device's logical sector size, so multiply by 512 to compare against LVM's
  # byte-based size reports.
  size_in_sectors="$(cat "${SYS_CLASS_BLOCK_ROOT}/${device_name}/size" 2>/dev/null || true)"
  size_in_sectors="${size_in_sectors//[[:space:]]/}"
  if [[ "${size_in_sectors}" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$((size_in_sectors * 512))"
    return 0
  fi

  return 1
}

pvresize_root_partition() {
  local partition_device="$1"
  local partition_device_name=""
  local current_pv_size_bytes=""
  local current_dev_size_bytes=""
  local current_partition_size_bytes=""
  local current_resize_target_bytes=""
  local updated_pv_size_bytes=""
  local command_output=""
  local command_status=0
  local had_errexit=0

  partition_device_name="${partition_device##*/}"
  if current_pv_size_bytes="$(read_lvm_value pvs --noheadings --units b --nosuffix -o pv_size "${partition_device}")"; then
    current_partition_size_bytes="$(read_block_device_size_bytes "${partition_device_name}" || true)"
    if [ -n "${current_partition_size_bytes}" ]; then
      current_resize_target_bytes="${current_partition_size_bytes}"
    elif current_dev_size_bytes="$(read_lvm_value pvs --noheadings --units b --nosuffix -o dev_size "${partition_device}")"; then
      current_resize_target_bytes="${current_dev_size_bytes}"
    fi

    if [ -n "${current_pv_size_bytes}" ] && [ -n "${current_resize_target_bytes}" ] && [ "${current_pv_size_bytes}" -ge "${current_resize_target_bytes}" ]; then
      return 0
    fi
  fi

  case $- in
    *e*)
      had_errexit=1
      set +e
      ;;
  esac
  command_output="$(pvresize "${partition_device}" 2>&1)"
  command_status=$?
  if [ "${had_errexit}" -eq 1 ]; then
    set -e
  fi
  printf '%s\n' "${command_output}"

  if [ "${command_status}" -eq 0 ]; then
    return 0
  fi

  if updated_pv_size_bytes="$(read_lvm_value pvs --noheadings --units b --nosuffix -o pv_size "${partition_device}")"; then
    if [ -n "${updated_pv_size_bytes}" ] && [ -n "${current_resize_target_bytes}" ] && [ "${updated_pv_size_bytes}" -ge "${current_resize_target_bytes}" ]; then
      return 0
    fi
  fi

  if [ "${command_status}" -ne 0 ]; then
    return "${command_status}"
  fi
}

lvextend_root_volume() {
  local root_source="$1"
  local canonical_root_source="$1"
  local root_vg_name=""
  local current_vg_free_bytes=""
  local updated_vg_free_bytes=""
  local command_output=""
  local command_status=0
  local had_errexit=0

  canonical_root_source="$(resolve_lvm_logical_volume_path "${root_source}" || true)"
  if [ -n "${canonical_root_source}" ]; then
    root_source="${canonical_root_source}"
  fi

  if root_vg_name="$(read_lvm_value lvs --noheadings -o vg_name "${root_source}")"; then
    if [ -n "${root_vg_name}" ] &&
      current_vg_free_bytes="$(read_lvm_value vgs --noheadings --units b --nosuffix -o vg_free "${root_vg_name}")" &&
      [ -n "${current_vg_free_bytes}" ] && [ "${current_vg_free_bytes}" -eq 0 ]; then
      return 0
    fi
  fi

  case $- in
    *e*)
      had_errexit=1
      set +e
      ;;
  esac
  command_output="$(lvextend -l +100%FREE "${root_source}" 2>&1)"
  command_status=$?
  if [ "${had_errexit}" -eq 1 ]; then
    set -e
  fi
  printf '%s\n' "${command_output}"

  if [ "${command_status}" -eq 0 ]; then
    return 0
  fi

  if [ -n "${root_vg_name}" ] &&
    updated_vg_free_bytes="$(read_lvm_value vgs --noheadings --units b --nosuffix -o vg_free "${root_vg_name}")"; then
    if [ -n "${updated_vg_free_bytes}" ] && [ "${updated_vg_free_bytes}" -eq 0 ]; then
      return 0
    fi
  fi

  if [ "${command_status}" -ne 0 ]; then
    return "${command_status}"
  fi
}

grow_root_filesystem() {
  local root_source root_fs partition_device partition_device_name partition_number parent_disk_name parent_disk_device
  local filesystem_resize_source=""
  local root_is_lvm=0
  local growpart_output=""
  local growpart_status=0
  local had_errexit=0
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
  parent_disk_name="$(resolve_parent_disk_name "${partition_device_name}" || true)"
  partition_number="$(cat "${SYS_CLASS_BLOCK_ROOT}/${partition_device_name}/partition" 2>/dev/null || true)"

  if [ -z "${partition_device}" ] || [ -z "${parent_disk_name}" ] || [ -z "${partition_number}" ]; then
    echo "Skipping root disk growth: unsupported root device layout (${root_source:-unknown})."
    return 0
  fi

  parent_disk_device="/dev/${parent_disk_name}"
  filesystem_resize_source="${root_source}"

  if is_lvm_root_source "${root_source}"; then
    root_is_lvm=1
    if ! command -v lvs >/dev/null 2>&1 || ! command -v pvs >/dev/null 2>&1 || ! command -v vgs >/dev/null 2>&1 || ! command -v pvresize >/dev/null 2>&1 || ! command -v lvextend >/dev/null 2>&1; then
      required_packages+=(lvm2)
    fi
  fi

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

  case $- in
    *e*)
      had_errexit=1
      set +e
      ;;
  esac
  growpart_output="$(growpart "${parent_disk_device}" "${partition_number}" 2>&1)"
  growpart_status=$?
  if [ "${had_errexit}" -eq 1 ]; then
    set -e
  fi
  printf '%s\n' "${growpart_output}"

  if [ "${growpart_status}" -ne 0 ]; then
    return "${growpart_status}"
  fi

  if [ "${root_is_lvm}" -eq 1 ]; then
    if ! filesystem_resize_source="$(resolve_lvm_logical_volume_path "${root_source}")"; then
      echo "Skipping root disk growth: unable to resolve a unique logical volume for ${root_source}."
      return 1
    fi
    pvresize_root_partition "${partition_device}"
    lvextend_root_volume "${filesystem_resize_source}"
  fi

  case "${root_fs}" in
    ext2|ext3|ext4)
      resize2fs "${filesystem_resize_source}"
      ;;
    xfs)
      had_errexit=0
      case $- in
        *e*)
          had_errexit=1
          set +e
          ;;
      esac
      growpart_output="$(xfs_growfs / 2>&1)"
      growpart_status=$?
      if [ "${had_errexit}" -eq 1 ]; then
        set -e
      fi
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
