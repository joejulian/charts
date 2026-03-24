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

version_gt() {
  local left="$1"
  local right="$2"

  [[ "$(printf '%s\n%s\n' "${left}" "${right}" | sort -V | tail -n1)" == "${left}" && "${left}" != "${right}" ]]
}

main() {
  local chart_dir chart_name base_chart_version head_chart_version base_app_version head_app_version
  local base_app_major base_app_minor base_app_patch head_app_major head_app_minor head_app_patch
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

    base_chart_version="$(chart_yaml_value "${BASE_REF}" "${chart_dir#${REPO_ROOT}/}" version)"
    head_chart_version="$(yq -r '.version // ""' "${chart_dir}/Chart.yaml")"
    base_app_version="$(chart_yaml_value "${BASE_REF}" "${chart_dir#${REPO_ROOT}/}" appVersion)"
    head_app_version="$(yq -r '.appVersion // ""' "${chart_dir}/Chart.yaml")"

    if [[ "${base_app_version}" == "${head_app_version}" ]]; then
      continue
    fi

    if ! version_gt "${head_chart_version}" "${base_chart_version}"; then
      echo "Chart ${chart_name}: appVersion changed (${base_app_version} -> ${head_app_version}) but chart version did not increase (${base_chart_version} -> ${head_chart_version})."
      failed=1
      continue
    fi

    if normalize_semver "${base_app_version}" >/dev/null && normalize_semver "${head_app_version}" >/dev/null \
      && normalize_semver "${base_chart_version}" >/dev/null && normalize_semver "${head_chart_version}" >/dev/null; then
      read -r base_app_major base_app_minor base_app_patch <<<"$(normalize_semver "${base_app_version}")"
      read -r head_app_major head_app_minor head_app_patch <<<"$(normalize_semver "${head_app_version}")"
      read -r base_chart_major base_chart_minor base_chart_patch <<<"$(normalize_semver "${base_chart_version}")"
      read -r head_chart_major head_chart_minor head_chart_patch <<<"$(normalize_semver "${head_chart_version}")"

      if [[ "${base_app_major}" == "${head_app_major}" && "${base_app_minor}" == "${head_app_minor}" && "${base_app_patch}" != "${head_app_patch}" ]]; then
        if [[ "${base_chart_major}" != "${head_chart_major}" || "${base_chart_minor}" != "${head_chart_minor}" || "${head_chart_patch}" -le "${base_chart_patch}" ]]; then
          echo "Chart ${chart_name}: upstream patch update (${base_app_version} -> ${head_app_version}) requires a chart patch bump (${base_chart_version} -> ${head_chart_version})."
          failed=1
        fi
      fi
    fi
  done

  if [[ "${failed}" -ne 0 ]]; then
    exit 1
  fi
}

main "$@"
