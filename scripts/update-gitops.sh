#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 3 ]] || { echo "Usage: $0 <gitops-repo-path> <environment> <full-image>"; exit 2; }
GITOPS_REPO="$1"
ENVIRONMENT="$2"
FULL_IMAGE="$3"
FILE="${GITOPS_REPO}/apps/sample-api/overlays/${ENVIRONMENT}/kustomization.yaml"
[[ -f "$FILE" ]] || { echo "GitOps kustomization not found: $FILE"; exit 1; }
IMAGE_REPOSITORY="${FULL_IMAGE%:*}"
IMAGE_TAG="${FULL_IMAGE##*:}"
python3 - "$FILE" "$IMAGE_REPOSITORY" "$IMAGE_TAG" <<'PY'
from pathlib import Path
import re, sys
p=Path(sys.argv[1]); repo=sys.argv[2]; tag=sys.argv[3]
text=p.read_text(encoding='utf-8')
pat=re.compile(r'(images:\s*\n\s*-\s*name:\s*sample-api\s*\n\s*newName:\s*)[^\n]+(\s*\n\s*newTag:\s*)[^\n]+', re.MULTILINE)
updated,n=pat.subn(rf'\g<1>{repo}\g<2>"{tag}"', text, count=1)
if n != 1: raise SystemExit('Could not locate sample-api image block.')
p.write_text(updated, encoding='utf-8', newline='\n')
PY
echo "Updated $FILE"
echo "Image: $FULL_IMAGE"
