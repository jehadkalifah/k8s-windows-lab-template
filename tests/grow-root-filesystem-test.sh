#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="${REPO_ROOT}/ansible/grow-root-filesystem.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

create_partition_sysfs() {
  local temp_dir="$1"
  local partition_name="$2"
  local parent_disk_name="$3"
  local partition_number="$4"
  local partition_size_sectors="${5:-4194304}"
  local sys_root="${temp_dir}/sys/class/block"
  local backing_partition_dir="${temp_dir}/devices/block/${parent_disk_name}/${partition_name}"

  mkdir -p "${backing_partition_dir}"
  printf '%s\n' "${partition_number}" >"${backing_partition_dir}/partition"
  printf '%s\n' "${partition_size_sectors}" >"${backing_partition_dir}/size"
  ln -sfn "${backing_partition_dir}" "${sys_root}/${partition_name}"
}

create_lvm_dm_sysfs() {
  local temp_dir="$1"
  local dm_name="${2:-dm-0}"
  local dm_mapper_name="${3:-vg-root}"
  local sys_root="${temp_dir}/sys/class/block"

  mkdir -p "${sys_root}/${dm_name}/slaves" "${sys_root}/${dm_name}/dm"
  printf '%s\n' 'LVM-mock' >"${sys_root}/${dm_name}/dm/uuid"
  printf '%s\n' "${dm_mapper_name}" >"${sys_root}/${dm_name}/dm/name"
}

create_install_lvm_mocks_script() {
  local script_path="$1"

  cat >"${script_path}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
target_dir="$1"

cat >"${target_dir}/lvs" <<'INNER'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "--noheadings" ] && [ "${2:-}" = "-o" ] && [ "${3:-}" = "vg_name" ]; then
  printf '%s\n' "${MOCK_LVS_VG_NAME:-vg}"
  exit "${MOCK_LVS_STATUS:-0}"
fi
if [ "${1:-}" = "--noheadings" ] && [ "${2:-}" = "-o" ] && [ "${3:-}" = "vg_name,lv_name" ] && [ "${4:-}" = "--separator" ] && [ "${5:-}" = "/" ]; then
  printf '%s\n' "${MOCK_LVS_LV_PATH:-vg/root}"
  exit "${MOCK_LVS_STATUS:-0}"
fi
if [ -n "${MOCK_LVS_OUTPUT:-}" ]; then
  printf '%s\n' "${MOCK_LVS_OUTPUT}"
fi
exit "${MOCK_LVS_STATUS:-0}"
INNER

cat >"${target_dir}/pvs" <<'INNER'
#!/usr/bin/env bash
set -euo pipefail
next_value_from_file() {
  local file_path="$1"
  local -a values=()
  mapfile -t values <"${file_path}"
  printf '%s\n' "${values[0]}"
  : >"${file_path}"
  for ((i = 1; i < ${#values[@]}; i++)); do
    printf '%s\n' "${values[i]}" >>"${file_path}"
  done
}
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-o" ]; then
    field="$2"
    break
  fi
  shift
done
case "${field:-}" in
  pv_size)
    if [ -n "${MOCK_PVS_PV_SIZE_FILE:-}" ] && [ -f "${MOCK_PVS_PV_SIZE_FILE}" ]; then
      next_value_from_file "${MOCK_PVS_PV_SIZE_FILE}"
    else
      printf '%s\n' "${MOCK_PVS_PV_SIZE:-1073741824}"
    fi
    ;;
  dev_size) printf '%s\n' "${MOCK_PVS_DEV_SIZE:-2147483648}" ;;
  *) exit 1 ;;
esac
INNER

cat >"${target_dir}/vgs" <<'INNER'
#!/usr/bin/env bash
set -euo pipefail
next_value_from_file() {
  local file_path="$1"
  local -a values=()
  mapfile -t values <"${file_path}"
  printf '%s\n' "${values[0]}"
  : >"${file_path}"
  for ((i = 1; i < ${#values[@]}; i++)); do
    printf '%s\n' "${values[i]}" >>"${file_path}"
  done
}
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-o" ]; then
    field="$2"
    break
  fi
  shift
done
case "${field:-}" in
  vg_free)
    if [ -n "${MOCK_VGS_VG_FREE_FILE:-}" ] && [ -f "${MOCK_VGS_VG_FREE_FILE}" ]; then
      next_value_from_file "${MOCK_VGS_VG_FREE_FILE}"
    else
      printf '%s\n' "${MOCK_VGS_VG_FREE:-1073741824}"
    fi
    ;;
  *) exit 1 ;;
esac
INNER

cat >"${target_dir}/pvresize" <<'INNER'
#!/usr/bin/env bash
set -euo pipefail
if [ -n "${MOCK_PVRESIZE_LOG:-}" ]; then
  printf '%s\n' "$1" >"${MOCK_PVRESIZE_LOG}"
fi
if [ -n "${MOCK_PVRESIZE_OUTPUT:-}" ]; then
  printf '%s\n' "${MOCK_PVRESIZE_OUTPUT}"
else
  printf '%s\n' 'Physical volume "/dev/sda3" changed'
fi
exit "${MOCK_PVRESIZE_STATUS:-0}"
INNER

cat >"${target_dir}/lvextend" <<'INNER'
#!/usr/bin/env bash
set -euo pipefail
if [ -n "${MOCK_LVEXTEND_LOG:-}" ]; then
  printf '%s\n' "$*" >"${MOCK_LVEXTEND_LOG}"
fi
if [ -n "${MOCK_LVEXTEND_OUTPUT:-}" ]; then
  printf '%s\n' "${MOCK_LVEXTEND_OUTPUT}"
else
  printf '%s\n' 'Logical volume successfully resized.'
fi
exit "${MOCK_LVEXTEND_STATUS:-0}"
INNER

/bin/chmod +x "${target_dir}/lvs" "${target_dir}/pvs" "${target_dir}/vgs" "${target_dir}/pvresize" "${target_dir}/lvextend"
EOF

  /bin/chmod +x "${script_path}"
}

make_mock_bin() {
  local bin_dir="$1"
  mkdir -p "${bin_dir}"

  cat >"${bin_dir}/bash" <<'EOF'
#!/bin/bash
exec /bin/bash "$@"
EOF

  cat >"${bin_dir}/basename" <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/basename "$@"
EOF

  cat >"${bin_dir}/cat" <<'EOF'
#!/usr/bin/env bash
exec /bin/cat "$@"
EOF

  cat >"${bin_dir}/find" <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/find "$@"
EOF

  cat >"${bin_dir}/dirname" <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/dirname "$@"
EOF

  cat >"${bin_dir}/grep" <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/grep "$@"
EOF

  cat >"${bin_dir}/head" <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/head "$@"
EOF

  cat >"${bin_dir}/readlink" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = "-f" ]; then
  case "$2" in
    /dev/mapper/vg-root) printf '/dev/dm-0\n' ;;
    /dev/sda1|/dev/sda3|/dev/nvme0n1p2) printf '%s\n' "$2" ;;
    *) exec /usr/bin/readlink -f "$2" ;;
  esac
else
  exec /usr/bin/readlink "$@"
fi
EOF

  cat >"${bin_dir}/findmnt" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "$4" = "/" ]; then
  case "$3" in
    SOURCE) printf '%s\n' "${MOCK_FINDMNT_SOURCE}" ;;
    FSTYPE) printf '%s\n' "${MOCK_FINDMNT_FSTYPE}" ;;
    *) exit 1 ;;
  esac
else
  exit 1
fi
EOF

  cat >"${bin_dir}/lsblk" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "lsblk should not be called in this test" >&2
exit 1
EOF

  cat >"${bin_dir}/growpart" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ -n "${MOCK_GROWPART_LOG:-}" ]; then
  printf '%s %s\n' "$1" "$2" >"${MOCK_GROWPART_LOG}"
fi
printf '%s\n' "${MOCK_GROWPART_OUTPUT:-CHANGED: disk expanded}"
exit "${MOCK_GROWPART_STATUS:-0}"
EOF

  create_install_lvm_mocks_script "${bin_dir}/install-lvm-mocks"
  "${bin_dir}/install-lvm-mocks" "${bin_dir}"

  cat >"${bin_dir}/resize2fs" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$1" >"${MOCK_RESIZE2FS_LOG}"
EOF

  cat >"${bin_dir}/xfs_growfs" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$1" >"${MOCK_XFS_GROWFS_LOG}"
if [ -n "${MOCK_XFS_GROWFS_OUTPUT:-}" ]; then
  printf '%s\n' "${MOCK_XFS_GROWFS_OUTPUT}"
fi
exit "${MOCK_XFS_GROWFS_STATUS:-0}"
EOF

  cat >"${bin_dir}/apt-get" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ -n "${MOCK_APT_LOG:-}" ]; then
  printf '%s\n' "$*" >>"${MOCK_APT_LOG}"
fi

if [ "$1" = "update" ]; then
  exit 0
fi

if [ "$1" = "install" ] && [ "$2" = "-y" ]; then
  shift 2
  for package in "$@"; do
    case "${package}" in
      cloud-guest-utils)
        /bin/cat >"${MOCK_BIN_DIR}/growpart" <<'INNER'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "${MOCK_GROWPART_OUTPUT:-CHANGED: disk expanded}"
exit "${MOCK_GROWPART_STATUS:-0}"
INNER
        /bin/chmod +x "${MOCK_BIN_DIR}/growpart"
        ;;
      lvm2)
        "${MOCK_BIN_DIR}/install-lvm-mocks" "${MOCK_BIN_DIR}"
        ;;
      e2fsprogs)
        /bin/cat >"${MOCK_BIN_DIR}/resize2fs" <<'INNER'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$1" >"${MOCK_RESIZE2FS_LOG}"
INNER
        /bin/chmod +x "${MOCK_BIN_DIR}/resize2fs"
        ;;
      xfsprogs)
        /bin/cat >"${MOCK_BIN_DIR}/xfs_growfs" <<'INNER'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$1" >"${MOCK_XFS_GROWFS_LOG}"
INNER
        /bin/chmod +x "${MOCK_BIN_DIR}/xfs_growfs"
        ;;
    esac
  done
  exit 0
fi

echo "unexpected apt-get invocation: $*" >&2
exit 1
EOF

  chmod +x "${bin_dir}"/*
}

test_resolve_direct_partition() {
  local temp_dir sys_root bin_dir result
  temp_dir="$(mktemp -d)"
  sys_root="${temp_dir}/sys/class/block"
  bin_dir="${temp_dir}/bin"
  mkdir -p "${sys_root}"
  create_partition_sysfs "${temp_dir}" "sda1" "sda" "1"
  make_mock_bin "${bin_dir}"

  PATH="${bin_dir}:/usr/bin:/bin"
  SYS_CLASS_BLOCK_ROOT="${sys_root}"
  export PATH SYS_CLASS_BLOCK_ROOT
  source "${HELPER}"
  result="$(resolve_backing_partition_device /dev/sda1)"
  [ "${result}" = "/dev/sda1" ] || fail "expected /dev/sda1, got ${result}"

  rm -rf "${temp_dir}"
}

test_resolve_lvm_partition() {
  local temp_dir sys_root bin_dir result
  temp_dir="$(mktemp -d)"
  sys_root="${temp_dir}/sys/class/block"
  bin_dir="${temp_dir}/bin"
  create_lvm_dm_sysfs "${temp_dir}"
  mkdir -p "${sys_root}/dm-0/slaves/sda3"
  create_partition_sysfs "${temp_dir}" "sda3" "sda" "3"
  make_mock_bin "${bin_dir}"

  PATH="${bin_dir}:/usr/bin:/bin"
  SYS_CLASS_BLOCK_ROOT="${sys_root}"
  export PATH SYS_CLASS_BLOCK_ROOT
  source "${HELPER}"
  result="$(resolve_backing_partition_device /dev/mapper/vg-root)"
  [ "${result}" = "/dev/sda3" ] || fail "expected /dev/sda3, got ${result}"

  rm -rf "${temp_dir}"
}

test_grow_lvm_ext_root_resizes_logical_volume() {
  local temp_dir sys_root bin_dir pvresize_log lvextend_log resize_log output
  temp_dir="$(mktemp -d)"
  sys_root="${temp_dir}/sys/class/block"
  bin_dir="${temp_dir}/bin"
  pvresize_log="${temp_dir}/pvresize.log"
  lvextend_log="${temp_dir}/lvextend.log"
  resize_log="${temp_dir}/resize2fs.log"

  create_lvm_dm_sysfs "${temp_dir}"
  mkdir -p "${sys_root}/dm-0/slaves/sda3"
  create_partition_sysfs "${temp_dir}" "sda3" "sda" "3"
  make_mock_bin "${bin_dir}"

  output="$(
    PATH="${bin_dir}:/usr/bin:/bin" \
    SYS_CLASS_BLOCK_ROOT="${sys_root}" \
    MOCK_FINDMNT_SOURCE="/dev/mapper/vg-root" \
    MOCK_FINDMNT_FSTYPE="ext4" \
    MOCK_PVS_PV_SIZE="1073741824" \
    MOCK_PVS_DEV_SIZE="2147483648" \
    MOCK_VGS_VG_FREE="1073741824" \
    MOCK_PVRESIZE_LOG="${pvresize_log}" \
    MOCK_LVEXTEND_LOG="${lvextend_log}" \
    MOCK_RESIZE2FS_LOG="${resize_log}" \
    bash -c 'source "'"${HELPER}"'"; grow_root_filesystem'
  )"

  grep -q 'CHANGED: disk expanded' <<<"${output}" || fail "expected growpart output to be printed"
  [ "$(cat "${pvresize_log}")" = "/dev/sda3" ] || fail "expected pvresize to run on /dev/sda3"
  [ "$(cat "${lvextend_log}")" = "-l +100%FREE /dev/vg/root" ] || fail "expected lvextend to target the canonical root logical volume"
  [ "$(cat "${resize_log}")" = "/dev/vg/root" ] || fail "expected resize2fs to run on the canonical root logical volume"

  rm -rf "${temp_dir}"
}

test_lvm_no_free_space_still_resizes_ext_filesystem() {
  local temp_dir sys_root bin_dir resize_log output
  temp_dir="$(mktemp -d)"
  sys_root="${temp_dir}/sys/class/block"
  bin_dir="${temp_dir}/bin"
  resize_log="${temp_dir}/resize2fs.log"

  create_lvm_dm_sysfs "${temp_dir}"
  mkdir -p "${sys_root}/dm-0/slaves/sda3"
  create_partition_sysfs "${temp_dir}" "sda3" "sda" "3"
  make_mock_bin "${bin_dir}"

  output="$(
    PATH="${bin_dir}:/usr/bin:/bin" \
    SYS_CLASS_BLOCK_ROOT="${sys_root}" \
    MOCK_FINDMNT_SOURCE="/dev/mapper/vg-root" \
    MOCK_FINDMNT_FSTYPE="ext4" \
    MOCK_RESIZE2FS_LOG="${resize_log}" \
    MOCK_PVS_PV_SIZE="2147483648" \
    MOCK_PVS_DEV_SIZE="2147483648" \
    MOCK_VGS_VG_FREE="0" \
    MOCK_GROWPART_OUTPUT="NOCHANGE: partition already fills the available space" \
    MOCK_GROWPART_STATUS="0" \
    MOCK_LVEXTEND_LOG="${temp_dir}/lvextend.log" \
    bash -c 'source "'"${HELPER}"'"; grow_root_filesystem'
  )"

  grep -q 'NOCHANGE: partition already fills the available space' <<<"${output}" || fail "expected NOCHANGE output to be printed"
  [ ! -f "${temp_dir}/lvextend.log" ] || fail "expected lvextend to be skipped when the volume group has no free space"
  [ "$(cat "${resize_log}")" = "/dev/vg/root" ] || fail "expected resize2fs to still run after growpart NOCHANGE"

  rm -rf "${temp_dir}"
}

test_direct_partition_growpart_nochange_still_resizes_ext_filesystem() {
  local temp_dir sys_root bin_dir resize_log output
  temp_dir="$(mktemp -d)"
  sys_root="${temp_dir}/sys/class/block"
  bin_dir="${temp_dir}/bin"
  resize_log="${temp_dir}/resize2fs.log"

  mkdir -p "${sys_root}"
  create_partition_sysfs "${temp_dir}" "sda1" "sda" "1"
  make_mock_bin "${bin_dir}"

  output="$(
    PATH="${bin_dir}:/usr/bin:/bin" \
    SYS_CLASS_BLOCK_ROOT="${sys_root}" \
    MOCK_FINDMNT_SOURCE="/dev/sda1" \
    MOCK_FINDMNT_FSTYPE="ext4" \
    MOCK_RESIZE2FS_LOG="${resize_log}" \
    MOCK_GROWPART_OUTPUT="NOCHANGE: partition already fills the available space" \
    MOCK_GROWPART_STATUS="0" \
    bash -c 'source "'"${HELPER}"'"; grow_root_filesystem'
  )"

  grep -q 'NOCHANGE: partition already fills the available space' <<<"${output}" || fail "expected NOCHANGE output to be printed for direct partitions"
  [ "$(cat "${resize_log}")" = "/dev/sda1" ] || fail "expected resize2fs to still run for direct partitions after growpart NOCHANGE"

  rm -rf "${temp_dir}"
}

test_pvresize_failure_still_fails_when_pv_does_not_grow() {
  local temp_dir sys_root bin_dir
  temp_dir="$(mktemp -d)"
  sys_root="${temp_dir}/sys/class/block"
  bin_dir="${temp_dir}/bin"

  create_lvm_dm_sysfs "${temp_dir}"
  mkdir -p "${sys_root}/dm-0/slaves/sda3"
  create_partition_sysfs "${temp_dir}" "sda3" "sda" "3"
  make_mock_bin "${bin_dir}"

  if PATH="${bin_dir}:/usr/bin:/bin" \
    SYS_CLASS_BLOCK_ROOT="${sys_root}" \
    MOCK_FINDMNT_SOURCE="/dev/mapper/vg-root" \
    MOCK_FINDMNT_FSTYPE="ext4" \
    MOCK_PVS_PV_SIZE="1073741824" \
    MOCK_PVS_DEV_SIZE="2147483648" \
    MOCK_PVRESIZE_STATUS="5" \
    bash -c 'source "'"${HELPER}"'"; grow_root_filesystem' >/dev/null 2>&1; then
    fail "expected grow_root_filesystem to fail when pvresize fails without changing the PV size"
  fi

  rm -rf "${temp_dir}"
}

test_pvresize_failure_is_tolerated_when_pv_matches_device_after_retry_check() {
  local temp_dir sys_root bin_dir resize_log pv_size_file output
  temp_dir="$(mktemp -d)"
  sys_root="${temp_dir}/sys/class/block"
  bin_dir="${temp_dir}/bin"
  resize_log="${temp_dir}/resize2fs.log"
  pv_size_file="${temp_dir}/pv-size-sequence.txt"

  create_lvm_dm_sysfs "${temp_dir}"
  mkdir -p "${sys_root}/dm-0/slaves/sda3"
  create_partition_sysfs "${temp_dir}" "sda3" "sda" "3"
  make_mock_bin "${bin_dir}"
  printf '%s\n%s\n' '1073741824' '2147483648' >"${pv_size_file}"

  output="$(
    PATH="${bin_dir}:/usr/bin:/bin" \
    SYS_CLASS_BLOCK_ROOT="${sys_root}" \
    MOCK_FINDMNT_SOURCE="/dev/mapper/vg-root" \
    MOCK_FINDMNT_FSTYPE="ext4" \
    MOCK_PVS_PV_SIZE_FILE="${pv_size_file}" \
    MOCK_PVS_DEV_SIZE="2147483648" \
    MOCK_PVRESIZE_STATUS="5" \
    MOCK_RESIZE2FS_LOG="${resize_log}" \
    bash -c 'source "'"${HELPER}"'"; grow_root_filesystem'
  )"

  [ "$(cat "${resize_log}")" = "/dev/vg/root" ] || fail "expected resize2fs to run when pvresize failure is recovered by the post-check"
  [ -z "$(cat "${pv_size_file}")" ] || fail "expected both pv_size sequence values to be consumed"
  grep -q 'Physical volume "/dev/sda3" changed' <<<"${output}" || fail "expected pvresize output to be printed for the recovered failure path"

  rm -rf "${temp_dir}"
}

test_lvextend_failure_still_fails_when_vg_free_remains() {
  local temp_dir sys_root bin_dir
  temp_dir="$(mktemp -d)"
  sys_root="${temp_dir}/sys/class/block"
  bin_dir="${temp_dir}/bin"

  create_lvm_dm_sysfs "${temp_dir}"
  mkdir -p "${sys_root}/dm-0/slaves/sda3"
  create_partition_sysfs "${temp_dir}" "sda3" "sda" "3"
  make_mock_bin "${bin_dir}"

  if PATH="${bin_dir}:/usr/bin:/bin" \
    SYS_CLASS_BLOCK_ROOT="${sys_root}" \
    MOCK_FINDMNT_SOURCE="/dev/mapper/vg-root" \
    MOCK_FINDMNT_FSTYPE="ext4" \
    MOCK_PVS_PV_SIZE="2147483648" \
    MOCK_PVS_DEV_SIZE="2147483648" \
    MOCK_VGS_VG_FREE="1073741824" \
    MOCK_LVEXTEND_STATUS="5" \
    bash -c 'source "'"${HELPER}"'"; grow_root_filesystem' >/dev/null 2>&1; then
    fail "expected grow_root_filesystem to fail when lvextend fails without consuming free extents"
  fi

  rm -rf "${temp_dir}"
}

test_lvextend_failure_is_tolerated_when_vg_free_is_zero_after_retry_check() {
  local temp_dir sys_root bin_dir resize_log vg_free_file output
  temp_dir="$(mktemp -d)"
  sys_root="${temp_dir}/sys/class/block"
  bin_dir="${temp_dir}/bin"
  resize_log="${temp_dir}/resize2fs.log"
  vg_free_file="${temp_dir}/vg-free-sequence.txt"

  create_lvm_dm_sysfs "${temp_dir}"
  mkdir -p "${sys_root}/dm-0/slaves/sda3"
  create_partition_sysfs "${temp_dir}" "sda3" "sda" "3"
  make_mock_bin "${bin_dir}"
  printf '%s\n%s\n' '1073741824' '0' >"${vg_free_file}"

  output="$(
    PATH="${bin_dir}:/usr/bin:/bin" \
    SYS_CLASS_BLOCK_ROOT="${sys_root}" \
    MOCK_FINDMNT_SOURCE="/dev/mapper/vg-root" \
    MOCK_FINDMNT_FSTYPE="ext4" \
    MOCK_PVS_PV_SIZE="2147483648" \
    MOCK_PVS_DEV_SIZE="2147483648" \
    MOCK_VGS_VG_FREE_FILE="${vg_free_file}" \
    MOCK_LVEXTEND_STATUS="5" \
    MOCK_RESIZE2FS_LOG="${resize_log}" \
    bash -c 'source "'"${HELPER}"'"; grow_root_filesystem'
  )"

  [ "$(cat "${resize_log}")" = "/dev/vg/root" ] || fail "expected resize2fs to run when lvextend failure is recovered by the post-check"
  [ -z "$(cat "${vg_free_file}")" ] || fail "expected both vg_free sequence values to be consumed"
  grep -q 'Logical volume successfully resized.' <<<"${output}" || fail "expected lvextend output to be printed for the recovered failure path"

  rm -rf "${temp_dir}"
}

test_grow_xfs_root_uses_xfs_growfs() {
  local temp_dir sys_root bin_dir xfs_log output
  temp_dir="$(mktemp -d)"
  sys_root="${temp_dir}/sys/class/block"
  bin_dir="${temp_dir}/bin"
  xfs_log="${temp_dir}/xfs_growfs.log"

  create_lvm_dm_sysfs "${temp_dir}"
  mkdir -p "${sys_root}/dm-0/slaves/sda3"
  create_partition_sysfs "${temp_dir}" "sda3" "sda" "3"
  make_mock_bin "${bin_dir}"

  output="$(
    PATH="${bin_dir}:/usr/bin:/bin" \
    SYS_CLASS_BLOCK_ROOT="${sys_root}" \
    MOCK_FINDMNT_SOURCE="/dev/mapper/vg-root" \
    MOCK_FINDMNT_FSTYPE="xfs" \
    MOCK_XFS_GROWFS_LOG="${xfs_log}" \
    bash -c 'source "'"${HELPER}"'"; grow_root_filesystem'
  )"

  grep -q 'CHANGED: disk expanded' <<<"${output}" || fail "expected growpart output for xfs path"
  [ "$(cat "${xfs_log}")" = "/" ] || fail "expected xfs_growfs to run on /"

  rm -rf "${temp_dir}"
}

test_xfs_nochange_does_not_fail() {
  local temp_dir sys_root bin_dir xfs_log output
  temp_dir="$(mktemp -d)"
  sys_root="${temp_dir}/sys/class/block"
  bin_dir="${temp_dir}/bin"
  xfs_log="${temp_dir}/xfs_growfs.log"

  create_lvm_dm_sysfs "${temp_dir}"
  mkdir -p "${sys_root}/dm-0/slaves/sda3"
  create_partition_sysfs "${temp_dir}" "sda3" "sda" "3"
  make_mock_bin "${bin_dir}"

  output="$(
    PATH="${bin_dir}:/usr/bin:/bin" \
    SYS_CLASS_BLOCK_ROOT="${sys_root}" \
    MOCK_FINDMNT_SOURCE="/dev/mapper/vg-root" \
    MOCK_FINDMNT_FSTYPE="xfs" \
    MOCK_GROWPART_OUTPUT="NOCHANGE: partition already fills the available space" \
    MOCK_GROWPART_STATUS="0" \
    MOCK_XFS_GROWFS_LOG="${xfs_log}" \
    MOCK_XFS_GROWFS_OUTPUT="data size unchanged, skipping" \
    MOCK_XFS_GROWFS_STATUS="1" \
    bash -c 'source "'"${HELPER}"'"; grow_root_filesystem'
  )"

  grep -q 'NOCHANGE: partition already fills the available space' <<<"${output}" || fail "expected NOCHANGE output for xfs path"
  grep -q 'data size unchanged, skipping' <<<"${output}" || fail "expected xfs no-change output to be printed"
  [ "$(cat "${xfs_log}")" = "/" ] || fail "expected xfs_growfs to run even after growpart NOCHANGE"

  rm -rf "${temp_dir}"
}

test_installs_missing_ext_tools() {
  local temp_dir sys_root bin_dir apt_log resize_log output
  temp_dir="$(mktemp -d)"
  sys_root="${temp_dir}/sys/class/block"
  bin_dir="${temp_dir}/bin"
  apt_log="${temp_dir}/apt.log"
  resize_log="${temp_dir}/resize2fs.log"

  create_lvm_dm_sysfs "${temp_dir}"
  mkdir -p "${sys_root}/dm-0/slaves/sda3"
  create_partition_sysfs "${temp_dir}" "sda3" "sda" "3"
  make_mock_bin "${bin_dir}"
  rm -f "${bin_dir}/growpart" "${bin_dir}/resize2fs"

  output="$(
    PATH="${bin_dir}" \
    SYS_CLASS_BLOCK_ROOT="${sys_root}" \
    MOCK_BIN_DIR="${bin_dir}" \
    MOCK_APT_LOG="${apt_log}" \
    MOCK_FINDMNT_SOURCE="/dev/mapper/vg-root" \
    MOCK_FINDMNT_FSTYPE="ext4" \
    MOCK_RESIZE2FS_LOG="${resize_log}" \
    bash -c 'source "'"${HELPER}"'"; grow_root_filesystem'
  )"

  grep -q 'update' "${apt_log}" || fail "expected apt-get update for missing ext tools"
  grep -q 'install -y cloud-guest-utils e2fsprogs' "${apt_log}" || fail "expected ext tool packages to be installed"
  grep -q 'CHANGED: disk expanded' <<<"${output}" || fail "expected growpart output after ext tool install"
  [ "$(cat "${resize_log}")" = "/dev/vg/root" ] || fail "expected resize2fs to run after installing ext tools"

  rm -rf "${temp_dir}"
}

test_installs_missing_xfs_tool() {
  local temp_dir sys_root bin_dir apt_log xfs_log output
  temp_dir="$(mktemp -d)"
  sys_root="${temp_dir}/sys/class/block"
  bin_dir="${temp_dir}/bin"
  apt_log="${temp_dir}/apt.log"
  xfs_log="${temp_dir}/xfs_growfs.log"

  create_lvm_dm_sysfs "${temp_dir}"
  mkdir -p "${sys_root}/dm-0/slaves/sda3"
  create_partition_sysfs "${temp_dir}" "sda3" "sda" "3"
  make_mock_bin "${bin_dir}"
  rm -f "${bin_dir}/xfs_growfs"

  output="$(
    PATH="${bin_dir}" \
    SYS_CLASS_BLOCK_ROOT="${sys_root}" \
    MOCK_BIN_DIR="${bin_dir}" \
    MOCK_APT_LOG="${apt_log}" \
    MOCK_FINDMNT_SOURCE="/dev/mapper/vg-root" \
    MOCK_FINDMNT_FSTYPE="xfs" \
    MOCK_XFS_GROWFS_LOG="${xfs_log}" \
    bash -c 'source "'"${HELPER}"'"; grow_root_filesystem'
  )"

  grep -q 'install -y xfsprogs' "${apt_log}" || fail "expected xfsprogs to be installed when xfs_growfs is missing"
  grep -q 'CHANGED: disk expanded' <<<"${output}" || fail "expected growpart output after xfs tool install"
  [ "$(cat "${xfs_log}")" = "/" ] || fail "expected xfs_growfs to run after installing xfs tools"

  rm -rf "${temp_dir}"
}

test_installs_missing_lvm_tools() {
  local temp_dir sys_root bin_dir apt_log pvresize_log lvextend_log resize_log output update_count
  temp_dir="$(mktemp -d)"
  sys_root="${temp_dir}/sys/class/block"
  bin_dir="${temp_dir}/bin"
  apt_log="${temp_dir}/apt.log"
  pvresize_log="${temp_dir}/pvresize.log"
  lvextend_log="${temp_dir}/lvextend.log"
  resize_log="${temp_dir}/resize2fs.log"

  create_lvm_dm_sysfs "${temp_dir}"
  mkdir -p "${sys_root}/dm-0/slaves/sda3"
  create_partition_sysfs "${temp_dir}" "sda3" "sda" "3"
  make_mock_bin "${bin_dir}"
  rm -f "${bin_dir}/lvs" "${bin_dir}/pvresize" "${bin_dir}/lvextend"
  rm -f "${bin_dir}/readlink"

  output="$(
    PATH="${bin_dir}" \
    SYS_CLASS_BLOCK_ROOT="${sys_root}" \
    MOCK_BIN_DIR="${bin_dir}" \
    MOCK_APT_LOG="${apt_log}" \
    MOCK_FINDMNT_SOURCE="/dev/mapper/vg-root" \
    MOCK_FINDMNT_FSTYPE="ext4" \
    MOCK_PVS_PV_SIZE="1073741824" \
    MOCK_PVS_DEV_SIZE="2147483648" \
    MOCK_VGS_VG_FREE="1073741824" \
    MOCK_PVRESIZE_LOG="${pvresize_log}" \
    MOCK_LVEXTEND_LOG="${lvextend_log}" \
    MOCK_RESIZE2FS_LOG="${resize_log}" \
    bash -c 'source "'"${HELPER}"'"; grow_root_filesystem'
  )"

  update_count="$(grep -c '^update$' "${apt_log}")"
  [ "${update_count}" = "1" ] || fail "expected exactly one apt-get update when installing lvm2"
  grep -q 'install -y lvm2' "${apt_log}" || fail "expected lvm2 to be installed when LVM tools are missing"
  [ "$(cat "${pvresize_log}")" = "/dev/sda3" ] || fail "expected pvresize to run after installing lvm2"
  [ "$(cat "${lvextend_log}")" = "-l +100%FREE /dev/vg/root" ] || fail "expected lvextend to run after installing lvm2"
  [ "$(cat "${resize_log}")" = "/dev/vg/root" ] || fail "expected resize2fs to run after installing lvm2"
  grep -q 'CHANGED: disk expanded' <<<"${output}" || fail "expected growpart output after lvm tool install"

  rm -rf "${temp_dir}"
}

test_installs_missing_lvm_and_xfs_tools() {
  local temp_dir sys_root bin_dir apt_log pvresize_log lvextend_log xfs_log output
  temp_dir="$(mktemp -d)"
  sys_root="${temp_dir}/sys/class/block"
  bin_dir="${temp_dir}/bin"
  apt_log="${temp_dir}/apt.log"
  pvresize_log="${temp_dir}/pvresize.log"
  lvextend_log="${temp_dir}/lvextend.log"
  xfs_log="${temp_dir}/xfs_growfs.log"

  create_lvm_dm_sysfs "${temp_dir}"
  mkdir -p "${sys_root}/dm-0/slaves/sda3"
  create_partition_sysfs "${temp_dir}" "sda3" "sda" "3"
  make_mock_bin "${bin_dir}"
  rm -f "${bin_dir}/lvs" "${bin_dir}/pvs" "${bin_dir}/vgs" "${bin_dir}/pvresize" "${bin_dir}/lvextend" "${bin_dir}/xfs_growfs" "${bin_dir}/readlink"

  output="$(
    PATH="${bin_dir}" \
    SYS_CLASS_BLOCK_ROOT="${sys_root}" \
    MOCK_BIN_DIR="${bin_dir}" \
    MOCK_APT_LOG="${apt_log}" \
    MOCK_FINDMNT_SOURCE="/dev/mapper/vg-root" \
    MOCK_FINDMNT_FSTYPE="xfs" \
    MOCK_PVS_PV_SIZE="1073741824" \
    MOCK_PVS_DEV_SIZE="2147483648" \
    MOCK_VGS_VG_FREE="1073741824" \
    MOCK_PVRESIZE_LOG="${pvresize_log}" \
    MOCK_LVEXTEND_LOG="${lvextend_log}" \
    MOCK_XFS_GROWFS_LOG="${xfs_log}" \
    bash -c 'source "'"${HELPER}"'"; grow_root_filesystem'
  )"

  grep -q 'install -y lvm2 xfsprogs' "${apt_log}" || fail "expected lvm2 and xfsprogs to be installed together for LVM-backed xfs roots"
  [ "$(cat "${pvresize_log}")" = "/dev/sda3" ] || fail "expected pvresize to run after installing lvm2 for xfs roots"
  [ "$(cat "${lvextend_log}")" = "-l +100%FREE /dev/vg/root" ] || fail "expected lvextend to run after installing lvm2 for xfs roots"
  [ "$(cat "${xfs_log}")" = "/" ] || fail "expected xfs_growfs to run after installing xfsprogs"
  grep -q 'CHANGED: disk expanded' <<<"${output}" || fail "expected growpart output after installing lvm and xfs tools"

  rm -rf "${temp_dir}"
}

test_installs_lvm2_for_partial_lvm_toolchain() {
  local temp_dir sys_root bin_dir apt_log pvresize_log lvextend_log resize_log output
  temp_dir="$(mktemp -d)"
  sys_root="${temp_dir}/sys/class/block"
  bin_dir="${temp_dir}/bin"
  apt_log="${temp_dir}/apt.log"
  pvresize_log="${temp_dir}/pvresize.log"
  lvextend_log="${temp_dir}/lvextend.log"
  resize_log="${temp_dir}/resize2fs.log"

  create_lvm_dm_sysfs "${temp_dir}"
  mkdir -p "${sys_root}/dm-0/slaves/sda3"
  create_partition_sysfs "${temp_dir}" "sda3" "sda" "3"
  make_mock_bin "${bin_dir}"
  rm -f "${bin_dir}/lvextend"

  output="$(
    PATH="${bin_dir}" \
    SYS_CLASS_BLOCK_ROOT="${sys_root}" \
    MOCK_BIN_DIR="${bin_dir}" \
    MOCK_APT_LOG="${apt_log}" \
    MOCK_FINDMNT_SOURCE="/dev/mapper/vg-root" \
    MOCK_FINDMNT_FSTYPE="ext4" \
    MOCK_PVS_PV_SIZE="1073741824" \
    MOCK_PVS_DEV_SIZE="2147483648" \
    MOCK_VGS_VG_FREE="1073741824" \
    MOCK_PVRESIZE_LOG="${pvresize_log}" \
    MOCK_LVEXTEND_LOG="${lvextend_log}" \
    MOCK_RESIZE2FS_LOG="${resize_log}" \
    bash -c 'source "'"${HELPER}"'"; grow_root_filesystem'
  )"

  grep -q 'install -y lvm2' "${apt_log}" || fail "expected lvm2 to be installed when lvextend is missing"
  [ "$(cat "${pvresize_log}")" = "/dev/sda3" ] || fail "expected pvresize to run after repairing the LVM toolchain"
  [ "$(cat "${lvextend_log}")" = "-l +100%FREE /dev/vg/root" ] || fail "expected lvextend to run after repairing the LVM toolchain"
  [ "$(cat "${resize_log}")" = "/dev/vg/root" ] || fail "expected resize2fs to run after repairing the LVM toolchain"
  grep -q 'CHANGED: disk expanded' <<<"${output}" || fail "expected growpart output after partial lvm tool install"

  rm -rf "${temp_dir}"
}

test_grow_nvme_root_uses_parent_disk_path() {
  local temp_dir sys_root bin_dir growpart_log output
  temp_dir="$(mktemp -d)"
  sys_root="${temp_dir}/sys/class/block"
  bin_dir="${temp_dir}/bin"
  growpart_log="${temp_dir}/growpart.log"

  create_lvm_dm_sysfs "${temp_dir}"
  mkdir -p "${sys_root}/dm-0/slaves/nvme0n1p2"
  create_partition_sysfs "${temp_dir}" "nvme0n1p2" "nvme0n1" "2"
  make_mock_bin "${bin_dir}"

  output="$(
    PATH="${bin_dir}:/usr/bin:/bin" \
    SYS_CLASS_BLOCK_ROOT="${sys_root}" \
    MOCK_FINDMNT_SOURCE="/dev/mapper/vg-root" \
    MOCK_FINDMNT_FSTYPE="ext4" \
    MOCK_RESIZE2FS_LOG="${temp_dir}/resize2fs.log" \
    MOCK_GROWPART_LOG="${growpart_log}" \
    bash -c 'source "'"${HELPER}"'"; grow_root_filesystem'
  )"

  grep -q 'CHANGED: disk expanded' <<<"${output}" || fail "expected growpart output for nvme path"
  [ "$(cat "${growpart_log}")" = "/dev/nvme0n1 2" ] || fail "expected growpart to target /dev/nvme0n1 partition 2"

  rm -rf "${temp_dir}"
}

test_resolve_direct_partition
test_resolve_lvm_partition
test_grow_lvm_ext_root_resizes_logical_volume
test_lvm_no_free_space_still_resizes_ext_filesystem
test_direct_partition_growpart_nochange_still_resizes_ext_filesystem
test_pvresize_failure_still_fails_when_pv_does_not_grow
test_pvresize_failure_is_tolerated_when_pv_matches_device_after_retry_check
test_lvextend_failure_still_fails_when_vg_free_remains
test_lvextend_failure_is_tolerated_when_vg_free_is_zero_after_retry_check
test_grow_xfs_root_uses_xfs_growfs
test_xfs_nochange_does_not_fail
test_installs_missing_ext_tools
test_installs_missing_xfs_tool
test_installs_missing_lvm_tools
test_installs_missing_lvm_and_xfs_tools
test_installs_lvm2_for_partial_lvm_toolchain
test_grow_nvme_root_uses_parent_disk_path

echo "PASS: grow-root-filesystem helper"
