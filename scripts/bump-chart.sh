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

main() {
  local chart_file chart_dir chart_name base_app_version current_app_version base_chart_version current_chart_version
  local major minor patch
  local -a changed_chart_files

  mapfile -t changed_chart_files < <(git -C "${REPO_ROOT}" diff --name-only -- charts/*/Chart.yaml)

  for chart_file in "${changed_chart_files[@]}"; do
    chart_dir="${REPO_ROOT}/$(dirname "${chart_file}")"
    chart_name="$(basename "${chart_dir}")"

    if ! git -C "${REPO_ROOT}" cat-file -e "HEAD:${chart_file}" 2>/dev/null; then
      continue
    fi

    base_app_version="$(git -C "${REPO_ROOT}" show "HEAD:${chart_file}" | yq -r '.appVersion // ""' -)"
    current_app_version="$(yq -r '.appVersion // ""' "${chart_dir}/Chart.yaml")"

    if [[ "${base_app_version}" == "${current_app_version}" ]]; then
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

    patch=$((patch + 1))
    yq -i ".version = \"${major}.${minor}.${patch}\"" "${chart_dir}/Chart.yaml"
  done
}

main "$@"
