#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE_REF="${1:-}"
HEAD_REF="${2:-HEAD}"

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

version_gt() {
  local left="$1"
  local right="$2"

  [[ "$(printf '%s\n%s\n' "${left}" "${right}" | sort -V | tail -n1)" == "${left}" && "${left}" != "${right}" ]]
}

main() {
  local chart_dir relative_chart_dir chart_name base_chart_version head_chart_version head_chart
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

    base_chart_version="$(chart_yaml_value "${BASE_REF}" "${relative_chart_dir}" version)"
    head_chart="$(chart_json_from_file "${chart_dir}/Chart.yaml")"
    head_chart_version="$(jq -r '.version' <<<"${head_chart}")"

    if ! version_gt "${head_chart_version}" "${base_chart_version}"; then
      echo "Chart ${chart_name}: packaged chart content changed but chart version did not increase (${base_chart_version} -> ${head_chart_version})."
      failed=1
      continue
    fi
  done

  if [[ "${failed}" -ne 0 ]]; then
    exit 1
  fi
}

main "$@"
