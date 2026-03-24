#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

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
  local base_major base_minor base_patch current_major current_minor current_patch

  if [[ "${base}" == "${current}" ]]; then
    echo 0
    return 0
  fi

  if ! read -r base_major base_minor base_patch <<<"$(normalize_semver "${base}")"; then
    echo 1
    return 0
  fi

  if ! read -r current_major current_minor current_patch <<<"$(normalize_semver "${current}")"; then
    echo 1
    return 0
  fi

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

required_chart_bump_level() {
  local chart_file="$1"
  local base_chart dep_name dep_version base_app_version current_app_version level dep_line
  local current_chart="${REPO_ROOT}/${chart_file}"
  declare -A base_deps=()
  declare -A current_deps=()

  base_chart="$(git -C "${REPO_ROOT}" show "HEAD:${chart_file}")"
  base_app_version="$(printf '%s' "${base_chart}" | yq -r '.appVersion // ""' -)"
  current_app_version="$(yq -r '.appVersion // ""' "${current_chart}")"
  level="$(version_change_level "${base_app_version}" "${current_app_version}")"

  while IFS=$'\t' read -r dep_name dep_version; do
    [[ -n "${dep_name}" ]] || continue
    base_deps["${dep_name}"]="${dep_version}"
  done < <(printf '%s' "${base_chart}" | yq -r '.dependencies[]? | [.name, (.version // "")] | @tsv' -)

  while IFS=$'\t' read -r dep_name dep_version; do
    [[ -n "${dep_name}" ]] || continue
    current_deps["${dep_name}"]="${dep_version}"
  done < <(yq -r '.dependencies[]? | [.name, (.version // "")] | @tsv' "${current_chart}")

  for dep_name in "${!base_deps[@]}"; do
    if [[ ! -v "current_deps[${dep_name}]" ]]; then
      level="$(max_level "${level}" 1)"
      continue
    fi

    level="$(max_level "${level}" "$(version_change_level "${base_deps[${dep_name}]}" "${current_deps[${dep_name}]}")")"
  done

  for dep_name in "${!current_deps[@]}"; do
    if [[ ! -v "base_deps[${dep_name}]" ]]; then
      level="$(max_level "${level}" 1)"
    fi
  done

  echo "${level}"
}

main() {
  local chart_file chart_dir chart_name base_chart_version current_chart_version required_level
  local major minor patch
  local -a changed_chart_files

  mapfile -t changed_chart_files < <(git -C "${REPO_ROOT}" diff --name-only -- charts/*/Chart.yaml)

  for chart_file in "${changed_chart_files[@]}"; do
    chart_dir="${REPO_ROOT}/$(dirname "${chart_file}")"
    chart_name="$(basename "${chart_dir}")"

    if ! git -C "${REPO_ROOT}" cat-file -e "HEAD:${chart_file}" 2>/dev/null; then
      continue
    fi

    required_level="$(required_chart_bump_level "${chart_file}")"
    if [[ "${required_level}" == "0" ]]; then
      continue
    fi

    base_chart_version="$(git -C "${REPO_ROOT}" show "HEAD:${chart_file}" | yq -r '.version // ""' -)"
    current_chart_version="$(yq -r '.version // ""' "${chart_dir}/Chart.yaml")"

    if [[ "${base_chart_version}" != "${current_chart_version}" ]]; then
      continue
    fi

    if ! read -r major minor patch <<<"$(normalize_semver "${current_chart_version}")"; then
      echo "Skipping ${chart_name}: chart version '${current_chart_version}' is not strict semver." >&2
      continue
    fi

    case "${required_level}" in
      3)
        major=$((major + 1))
        minor=0
        patch=0
        ;;
      2)
        minor=$((minor + 1))
        patch=0
        ;;
      1)
        patch=$((patch + 1))
        ;;
    esac

    yq -i ".version = \"${major}.${minor}.${patch}\"" "${chart_dir}/Chart.yaml"
  done
}

main "$@"
