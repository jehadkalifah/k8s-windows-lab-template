#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="${REPO_ROOT}/ansible/grow-root-filesystem.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

make_mock_bin() {
  local bin_dir="$1"
  mkdir -p "${bin_dir}"

  cat >"${bin_dir}/readlink" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = "-f" ]; then
  case "$2" in
    /dev/mapper/vg-root) printf '/dev/dm-0\n' ;;
    *) printf '%s\n' "$2" ;;
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
if [ "$1" = "-no" ] && [ "$3" = "/dev/sda3" ]; then
  case "$2" in
    PKNAME) printf 'sda\n' ;;
    PARTN) printf '3\n' ;;
    *) exit 1 ;;
  esac
else
  exit 1
fi
EOF

  cat >"${bin_dir}/growpart" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "${MOCK_GROWPART_OUTPUT:-CHANGED: disk expanded}"
exit "${MOCK_GROWPART_STATUS:-0}"
EOF

  cat >"${bin_dir}/resize2fs" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$1" >"${MOCK_RESIZE2FS_LOG}"
EOF

  cat >"${bin_dir}/xfs_growfs" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$1" >"${MOCK_XFS_GROWFS_LOG}"
EOF

  cat >"${bin_dir}/apt-get" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "apt-get should not be called in this test" >&2
exit 1
EOF

  chmod +x "${bin_dir}"/*
}

test_resolve_direct_partition() {
  local temp_dir sys_root bin_dir result
  temp_dir="$(mktemp -d)"
  sys_root="${temp_dir}/sys/class/block"
  bin_dir="${temp_dir}/bin"
  mkdir -p "${sys_root}/sda1"
  : >"${sys_root}/sda1/partition"
  make_mock_bin "${bin_dir}"

  PATH="${bin_dir}:/usr/bin:/bin"
  SYS_CLASS_BLOCK_ROOT="${sys_root}"
  source "${HELPER}"
  result="$(PATH="${bin_dir}:/usr/bin:/bin" SYS_CLASS_BLOCK_ROOT="${sys_root}" resolve_backing_partition_device /dev/sda1)"
  [ "${result}" = "/dev/sda1" ] || fail "expected /dev/sda1, got ${result}"

  rm -rf "${temp_dir}"
}

test_resolve_lvm_partition() {
  local temp_dir sys_root bin_dir result
  temp_dir="$(mktemp -d)"
  sys_root="${temp_dir}/sys/class/block"
  bin_dir="${temp_dir}/bin"
  mkdir -p "${sys_root}/dm-0/slaves/sda3" "${sys_root}/sda3"
  : >"${sys_root}/sda3/partition"
  make_mock_bin "${bin_dir}"

  PATH="${bin_dir}:/usr/bin:/bin"
  SYS_CLASS_BLOCK_ROOT="${sys_root}"
  source "${HELPER}"
  result="$(PATH="${bin_dir}:/usr/bin:/bin" SYS_CLASS_BLOCK_ROOT="${sys_root}" resolve_backing_partition_device /dev/mapper/vg-root)"
  [ "${result}" = "/dev/sda3" ] || fail "expected /dev/sda3, got ${result}"

  rm -rf "${temp_dir}"
}

test_grow_lvm_ext_root_resizes_logical_volume() {
  local temp_dir sys_root bin_dir resize_log output
  temp_dir="$(mktemp -d)"
  sys_root="${temp_dir}/sys/class/block"
  bin_dir="${temp_dir}/bin"
  resize_log="${temp_dir}/resize2fs.log"

  mkdir -p "${sys_root}/dm-0/slaves/sda3" "${sys_root}/sda3"
  : >"${sys_root}/sda3/partition"
  make_mock_bin "${bin_dir}"

  output="$(
    PATH="${bin_dir}:/usr/bin:/bin" \
    SYS_CLASS_BLOCK_ROOT="${sys_root}" \
    MOCK_FINDMNT_SOURCE="/dev/mapper/vg-root" \
    MOCK_FINDMNT_FSTYPE="ext4" \
    MOCK_RESIZE2FS_LOG="${resize_log}" \
    bash -c 'source "'"${HELPER}"'"; grow_root_filesystem'
  )"

  grep -q 'CHANGED: disk expanded' <<<"${output}" || fail "expected growpart output to be printed"
  [ "$(cat "${resize_log}")" = "/dev/mapper/vg-root" ] || fail "expected resize2fs to run on /dev/mapper/vg-root"

  rm -rf "${temp_dir}"
}

test_growpart_nochange_skips_filesystem_resize() {
  local temp_dir sys_root bin_dir output
  temp_dir="$(mktemp -d)"
  sys_root="${temp_dir}/sys/class/block"
  bin_dir="${temp_dir}/bin"

  mkdir -p "${sys_root}/dm-0/slaves/sda3" "${sys_root}/sda3"
  : >"${sys_root}/sda3/partition"
  make_mock_bin "${bin_dir}"

  output="$(
    PATH="${bin_dir}:/usr/bin:/bin" \
    SYS_CLASS_BLOCK_ROOT="${sys_root}" \
    MOCK_FINDMNT_SOURCE="/dev/mapper/vg-root" \
    MOCK_FINDMNT_FSTYPE="ext4" \
    MOCK_GROWPART_OUTPUT="NOCHANGE: partition already fills the available space" \
    MOCK_GROWPART_STATUS="1" \
    bash -c 'source "'"${HELPER}"'"; grow_root_filesystem'
  )"

  grep -q 'NOCHANGE: partition already fills the available space' <<<"${output}" || fail "expected NOCHANGE output to be printed"

  rm -rf "${temp_dir}"
}

test_grow_xfs_root_uses_xfs_growfs() {
  local temp_dir sys_root bin_dir xfs_log output
  temp_dir="$(mktemp -d)"
  sys_root="${temp_dir}/sys/class/block"
  bin_dir="${temp_dir}/bin"
  xfs_log="${temp_dir}/xfs_growfs.log"

  mkdir -p "${sys_root}/dm-0/slaves/sda3" "${sys_root}/sda3"
  : >"${sys_root}/sda3/partition"
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

test_resolve_direct_partition
test_resolve_lvm_partition
test_grow_lvm_ext_root_resizes_logical_volume
test_growpart_nochange_skips_filesystem_resize
test_grow_xfs_root_uses_xfs_growfs

echo "PASS: grow-root-filesystem helper"
