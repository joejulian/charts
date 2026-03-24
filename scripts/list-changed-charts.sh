#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ "$#" -ne 2 ]]; then
  echo "usage: $0 <base-ref> <head-ref>" >&2
  exit 1
fi

base_ref="$1"
head_ref="$2"

git -C "${REPO_ROOT}" diff --name-only "${base_ref}" "${head_ref}" -- \
  charts \
  ci/values \
| awk -F/ '
    $1 == "charts" && NF >= 2 { print "'"${REPO_ROOT}"'/charts/" $2 }
    $1 == "ci" && $2 == "values" && NF == 3 {
      chart = $3
      sub(/\.yaml$/, "", chart)
      print "'"${REPO_ROOT}"'/charts/" chart
    }
  ' \
| sort -u \
| while read -r chart_dir; do
    [[ -d "${chart_dir}" ]] && printf '%s\n' "${chart_dir}"
  done
