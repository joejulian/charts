#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE_REF="${1:-}"
HEAD_REF="${2:-HEAD}"

if [[ -z "${BASE_REF}" ]]; then
  find "${REPO_ROOT}/charts" -mindepth 1 -maxdepth 1 -type d | sort
  exit 0
fi

if [[ "${BASE_REF}" =~ ^0+$ ]]; then
  find "${REPO_ROOT}/charts" -mindepth 1 -maxdepth 1 -type d | sort
  exit 0
fi

git -C "${REPO_ROOT}" diff --name-only "${BASE_REF}" "${HEAD_REF}" -- charts \
  | awk -F/ 'NF >= 2 {print $1 "/" $2}' \
  | sort -u \
  | sed "s#^#${REPO_ROOT}/#"
