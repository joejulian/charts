#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE_REF="${1:-}"
HEAD_REF="${2:-HEAD}"

# shellcheck source=scripts/chart-version-lib.sh
source "${REPO_ROOT}/scripts/chart-version-lib.sh"

chart_json_from_file() {
  local chart_file="$1"
  python3 "${REPO_ROOT}/scripts/chart_yaml.py" json --file "${chart_file}"
}

chart_json_from_ref() {
  local ref="$1"
  local chart_dir="$2"
  git -C "${REPO_ROOT}" show "${ref}:${chart_dir}/Chart.yaml" 2>/dev/null | python3 "${REPO_ROOT}/scripts/chart_yaml.py" json
}

chart_yaml_value() {
  local ref="$1"
  local chart_dir="$2"
  local key="$3"

  chart_json_from_ref "${ref}" "${chart_dir}" | jq -r --arg key "${key}" '.[$key]'
}

required_chart_bump_level() {
  local chart_dir="$1"
  local relative_chart_dir="${chart_dir#"${REPO_ROOT}"/}"
  local base_chart head_chart dep_name dep_version base_app_version head_app_version level
  declare -A base_deps=()
  declare -A head_deps=()

  base_chart="$(chart_json_from_ref "${BASE_REF}" "${relative_chart_dir}")"
  head_chart="$(chart_json_from_file "${chart_dir}/Chart.yaml")"
  base_app_version="$(jq -r '.appVersion' <<<"${base_chart}")"
  head_app_version="$(jq -r '.appVersion' <<<"${head_chart}")"
  level="$(version_change_level "${base_app_version}" "${head_app_version}")"

  while IFS=$'\t' read -r dep_name dep_version; do
    [[ -n "${dep_name}" ]] || continue
    base_deps["${dep_name}"]="${dep_version}"
  done < <(jq -r '.dependencies | to_entries[]? | [.key, .value] | @tsv' <<<"${base_chart}")

  while IFS=$'\t' read -r dep_name dep_version; do
    [[ -n "${dep_name}" ]] || continue
    head_deps["${dep_name}"]="${dep_version}"
  done < <(jq -r '.dependencies | to_entries[]? | [.key, .value] | @tsv' <<<"${head_chart}")

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
  local chart_dir relative_chart_dir chart_name base_chart_version head_chart_version required_level head_chart
  local base_chart_major base_chart_minor base_chart_patch head_chart_major head_chart_minor head_chart_patch
  local failed=0
  local -a changed_charts

  if [[ -z "${BASE_REF}" || "${BASE_REF}" =~ ^0+$ ]]; then
    echo "No usable base ref provided; skipping chart version bump check."
    return 0
  fi

  mapfile -t changed_charts < <("${REPO_ROOT}/scripts/changed-charts.sh" "${BASE_REF}" "${HEAD_REF}")

  for chart_dir in "${changed_charts[@]}"; do
    relative_chart_dir="${chart_dir#"${REPO_ROOT}"/}"
    chart_name="$(basename "${chart_dir}")"

    if ! git -C "${REPO_ROOT}" cat-file -e "${BASE_REF}:${relative_chart_dir}/Chart.yaml" 2>/dev/null; then
      continue
    fi

    required_level="$(required_chart_bump_level "${chart_dir}")"
    if [[ "${required_level}" == "0" ]]; then
      required_level=1
    fi

    base_chart_version="$(chart_yaml_value "${BASE_REF}" "${relative_chart_dir}" version)"
    head_chart="$(chart_json_from_file "${chart_dir}/Chart.yaml")"
    head_chart_version="$(jq -r '.version' <<<"${head_chart}")"

    if ! version_gt "${head_chart_version}" "${base_chart_version}"; then
      echo "Chart ${chart_name}: packaged chart content changed but chart version did not increase (${base_chart_version} -> ${head_chart_version})."
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
