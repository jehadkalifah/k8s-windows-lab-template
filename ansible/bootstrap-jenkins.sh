#!/usr/bin/env bash
set -euo pipefail

JENKINS_VERSION="${1:-2.568.3}"

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

echo "===================================================="
echo " Jenkins VM bootstrap"
echo "===================================================="
echo "Jenkins LTS: ${JENKINS_VERSION}"
echo "Java:        OpenJDK 21"
echo "Port:        8080"
echo "Context:     /jenkins"
echo

apt-get update
apt-get install -y   ca-certificates   curl   fontconfig   gnupg   openjdk-21-jre   wget

install -m 0755 -d /etc/apt/keyrings

wget -q -O /etc/apt/keyrings/jenkins-keyring.asc   https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key

cat >/etc/apt/sources.list.d/jenkins.list <<'EOF'
deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/
EOF

apt-get update

if ! apt-cache madison jenkins | awk '{print $3}' | grep -Fxq "${JENKINS_VERSION}"; then
  echo "ERROR: Jenkins ${JENKINS_VERSION} was not found in the stable repository." >&2
  echo "Available versions:" >&2
  apt-cache madison jenkins >&2 || true
  exit 1
fi

apt-get install -y "jenkins=${JENKINS_VERSION}"
apt-mark hold jenkins >/dev/null

mkdir -p /etc/systemd/system/jenkins.service.d
cat >/etc/systemd/system/jenkins.service.d/override.conf <<'EOF'
[Service]
Environment="JENKINS_PREFIX=/jenkins"
EOF

systemctl daemon-reload
systemctl enable jenkins
systemctl restart jenkins

echo "Waiting for Jenkins..."
for i in $(seq 1 120); do
  if curl -fsS --max-time 3 http://127.0.0.1:8080/jenkins/login >/dev/null 2>&1; then
    break
  fi
  sleep 3
done

if ! curl -fsS --max-time 3 http://127.0.0.1:8080/jenkins/login >/dev/null 2>&1; then
  echo "ERROR: Jenkins did not become reachable on /jenkins." >&2
  systemctl --no-pager --full status jenkins >&2 || true
  journalctl -u jenkins --no-pager -n 100 >&2 || true
  exit 1
fi

echo
echo "Jenkins is running:"
systemctl is-active jenkins
java -version 2>&1 | head -3
jenkins --version || true
echo
echo "Local URL:"
echo "  http://127.0.0.1:8080/jenkins/"
