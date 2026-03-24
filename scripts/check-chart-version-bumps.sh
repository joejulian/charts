#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE_REF="${1:-}"
HEAD_REF="${2:-HEAD}"

chart_yaml_value() {
  local ref="$1"
  local chart_dir="$2"
  local key="$3"

  git -C "${REPO_ROOT}" show "${ref}:${chart_dir}/Chart.yaml" 2>/dev/null \
    | yq -r ".${key} // \"\"" -
}

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
  local chart_dir="$1"
  local base_chart dep_name dep_version base_app_version head_app_version level
  declare -A base_deps=()
  declare -A head_deps=()

  base_chart="$(git -C "${REPO_ROOT}" show "${BASE_REF}:${chart_dir#${REPO_ROOT}/}/Chart.yaml")"
  base_app_version="$(printf '%s' "${base_chart}" | yq -r '.appVersion // ""' -)"
  head_app_version="$(yq -r '.appVersion // ""' "${chart_dir}/Chart.yaml")"
  level="$(version_change_level "${base_app_version}" "${head_app_version}")"

  while IFS=$'\t' read -r dep_name dep_version; do
    [[ -n "${dep_name}" ]] || continue
    base_deps["${dep_name}"]="${dep_version}"
  done < <(printf '%s' "${base_chart}" | yq -r '.dependencies[]? | [.name, (.version // "")] | @tsv' -)

  while IFS=$'\t' read -r dep_name dep_version; do
    [[ -n "${dep_name}" ]] || continue
    head_deps["${dep_name}"]="${dep_version}"
  done < <(yq -r '.dependencies[]? | [.name, (.version // "")] | @tsv' "${chart_dir}/Chart.yaml")

  for dep_name in "${!base_deps[@]}"; do
    if [[ ! -v "head_deps[${dep_name}]" ]]; then
      level="$(max_level "${level}" 1)"
      continue
    fi

    level="$(max_level "${level}" "$(version_change_level "${base_deps[${dep_name}]}" "${head_deps[${dep_name}]}")")"
  done

  for dep_name in "${!head_deps[@]}"; do
    if [[ ! -v "base_deps[${dep_name}]" ]]; then
      level="$(max_level "${level}" 1)"
    fi
  done

  echo "${level}"
}

version_gt() {
  local left="$1"
  local right="$2"

  [[ "$(printf '%s\n%s\n' "${left}" "${right}" | sort -V | tail -n1)" == "${left}" && "${left}" != "${right}" ]]
}

main() {
  local chart_dir chart_name base_chart_version head_chart_version required_level
  local base_chart_major base_chart_minor base_chart_patch head_chart_major head_chart_minor head_chart_patch
  local failed=0
  local -a changed_charts

  if [[ -z "${BASE_REF}" || "${BASE_REF}" =~ ^0+$ ]]; then
    echo "No usable base ref provided; skipping chart version bump check."
    return 0
  fi

  mapfile -t changed_charts < <("${REPO_ROOT}/scripts/changed-charts.sh" "${BASE_REF}" "${HEAD_REF}")

  for chart_dir in "${changed_charts[@]}"; do
    chart_name="$(basename "${chart_dir}")"

    if ! git -C "${REPO_ROOT}" cat-file -e "${BASE_REF}:${chart_dir#${REPO_ROOT}/}/Chart.yaml" 2>/dev/null; then
      continue
    fi

    required_level="$(required_chart_bump_level "${chart_dir}")"
    if [[ "${required_level}" == "0" ]]; then
      continue
    fi

    base_chart_version="$(chart_yaml_value "${BASE_REF}" "${chart_dir#${REPO_ROOT}/}" version)"
    head_chart_version="$(yq -r '.version // ""' "${chart_dir}/Chart.yaml")"

    if ! version_gt "${head_chart_version}" "${base_chart_version}"; then
      echo "Chart ${chart_name}: Chart.yaml dependency or appVersion changed but chart version did not increase (${base_chart_version} -> ${head_chart_version})."
      failed=1
      continue
    fi

    if normalize_semver "${base_chart_version}" >/dev/null && normalize_semver "${head_chart_version}" >/dev/null; then
      read -r base_chart_major base_chart_minor base_chart_patch <<<"$(normalize_semver "${base_chart_version}")"
      read -r head_chart_major head_chart_minor head_chart_patch <<<"$(normalize_semver "${head_chart_version}")"

      case "${required_level}" in
        3)
          if (( head_chart_major <= base_chart_major )); then
            echo "Chart ${chart_name}: major Chart.yaml change requires a chart major bump (${base_chart_version} -> ${head_chart_version})."
            failed=1
          fi
          ;;
        2)
          if (( head_chart_major != base_chart_major || head_chart_minor <= base_chart_minor )); then
            echo "Chart ${chart_name}: minor Chart.yaml change requires a chart minor bump (${base_chart_version} -> ${head_chart_version})."
            failed=1
          fi
          ;;
        1)
          if (( head_chart_major != base_chart_major || head_chart_minor != base_chart_minor || head_chart_patch <= base_chart_patch )); then
            echo "Chart ${chart_name}: patch Chart.yaml change requires a chart patch bump (${base_chart_version} -> ${head_chart_version})."
            failed=1
          fi
          ;;
      esac
    fi
  done

  if [[ "${failed}" -ne 0 ]]; then
    exit 1
  fi
}

main "$@"
