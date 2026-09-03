#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
failed=0

while IFS=: read -r file line value; do
  repository="${value#*repository:}"
  repository="${repository%%#*}"
  repository="${repository//[\"\']/}"
  repository="${repository//[[:space:]]/}"
  first_component="${repository%%/*}"

  if [[ "${first_component}" != *.* && "${first_component}" != *:* && "${first_component}" != "localhost" ]]; then
    echo "${file#${repo_root}/}:${line}: image repository '${repository}' must include an explicit registry" >&2
    failed=1
  fi
done < <(grep -R -n -E "^[[:space:]]+repository:[[:space:]]*[\"']?[A-Za-z0-9._/-]+[\"']?([[:space:]]*#.*)?$" "${repo_root}/charts" --include='values.yaml')

exit "${failed}"
