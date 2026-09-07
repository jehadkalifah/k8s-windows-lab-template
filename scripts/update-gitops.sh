#!/bin/sh
set -eu

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <gitops-repo-path> <environment> <full-image>" >&2
  exit 2
fi

GITOPS_REPO="$1"
ENVIRONMENT="$2"
FULL_IMAGE="$3"
FILE="${GITOPS_REPO}/apps/sample-api/overlays/${ENVIRONMENT}/kustomization.yaml"

if [ ! -f "${FILE}" ]; then
  echo "GitOps kustomization not found: ${FILE}" >&2
  exit 1
fi

IMAGE_REPOSITORY="${FULL_IMAGE%:*}"
IMAGE_TAG="${FULL_IMAGE##*:}"
TMP="${FILE}.tmp"

awk -v repo="${IMAGE_REPOSITORY}" -v tag="${IMAGE_TAG}" '
  /^[[:space:]]*-[[:space:]]*name:[[:space:]]*sample-api[[:space:]]*$/ {
    in_target=1
    print
    next
  }
  in_target && /^[[:space:]]*newName:/ {
    sub(/newName:.*/, "newName: " repo)
    print
    next
  }
  in_target && /^[[:space:]]*newTag:/ {
    sub(/newTag:.*/, "newTag: \"" tag "\"")
    print
    in_target=0
    next
  }
  { print }
' "${FILE}" > "${TMP}"

mv "${TMP}" "${FILE}"
echo "Updated ${FILE}"
echo "Image: ${FULL_IMAGE}"
