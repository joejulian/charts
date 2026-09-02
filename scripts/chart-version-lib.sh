#!/usr/bin/env bash

normalize_semver() {
  local value="${1#v}"

  if [[ "${value}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    printf '%s %s %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
    return 0
  fi

  return 1
}

version_change_level() {
  local base="$1"
  local current="$2"
  local base_parts current_parts
  local base_major base_minor base_patch current_major current_minor current_patch

  if [[ "${base}" == "${current}" ]]; then
    echo 0
    return 0
  fi

  if ! base_parts="$(normalize_semver "${base}")"; then
    echo 1
    return 0
  fi

  if ! current_parts="$(normalize_semver "${current}")"; then
    echo 1
    return 0
  fi

  read -r base_major base_minor base_patch <<<"${base_parts}"
  read -r current_major current_minor current_patch <<<"${current_parts}"

  if (( current_major != base_major )); then
    echo 3
  elif (( current_minor != base_minor )); then
    echo 2
  elif (( current_patch != base_patch )); then
    echo 1
  else
    echo 0
  fi
}

max_level() {
  local current="$1"
  local candidate="$2"

  if (( candidate > current )); then
    echo "${candidate}"
  else
    echo "${current}"
  fi
}
