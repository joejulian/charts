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
    echo "${file#"${repo_root}"/}:${line}: image repository '${repository}' must include an explicit registry" >&2
    failed=1
  fi
done < <(grep -R -n -E "^[[:space:]]+repository:[[:space:]]*[\"']?[A-Za-z0-9._/-]+[\"']?([[:space:]]*#.*)?$" "${repo_root}/charts" --include='values.yaml')

while IFS=: read -r file line value; do
  image="${value#*image:}"
  image="${image%%#*}"
  image="${image//[\"\']/}"
  image="${image//[[:space:]]/}"
  first_component="${image%%/*}"

  if [[ "${first_component}" != *.* && "${first_component}" != *:* && "${first_component}" != "localhost" ]]; then
    echo "${file#"${repo_root}"/}:${line}: image '${image}' must include an explicit registry" >&2
    failed=1
  fi

  repository="${image%@*}"
  last_component="${repository##*/}"
  if [[ "${last_component}" == *:* ]]; then
    repository="${repository%:*}"
  fi
  previous_line="$(sed -n "$((line - 1))p" "${file}")"
  previous_line="${previous_line#*# }"
  if [[ "${previous_line}" != "renovate: image=${repository}" ]]; then
    echo "${file#"${repo_root}"/}:${line}: literal image '${image}' needs a matching Renovate annotation immediately above it" >&2
    failed=1
  fi
done < <(grep -R -n -E "^[[:space:]]+image:[[:space:]]*[\"']?[A-Za-z0-9._/-]+(:[^[:space:]\"']+|@sha256:[a-f0-9]{64})[\"']?([[:space:]]*#.*)?$" "${repo_root}/charts" --include='*.yaml')

exit "${failed}"
