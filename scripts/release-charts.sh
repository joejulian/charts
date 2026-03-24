#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OWNER="${GITHUB_REPOSITORY_OWNER:-joejulian}"
OCI_REPO="oci://ghcr.io/${OWNER}/charts"
DIST_DIR="${REPO_ROOT}/.dist"

mkdir -p "${DIST_DIR}"

release_chart() {
  local chart_dir="$1"
  local chart_name version package tag

  chart_name="$(basename "${chart_dir}")"
  version="$(helm show chart "${chart_dir}" | awk '/^version:/ {print $2}')"
  tag="${chart_name}-${version}"

  if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
    echo "Skipping ${chart_name}; tag ${tag} already exists"
    return
  fi

  if grep -q '^dependencies:' "${chart_dir}/Chart.yaml" 2>/dev/null; then
    helm dependency build "${chart_dir}"
  fi

  package="$(helm package "${chart_dir}" -d "${DIST_DIR}" | awk '{print $NF}')"
  helm push "${package}" "${OCI_REPO}"
  git tag -a "${tag}" -m "Release ${chart_name} ${version}"
  gh release create "${tag}" "${package}" --title "${chart_name} ${version}" --notes "Automated release for ${chart_name} ${version}."
}

main() {
  local base_ref="${1:-}"
  local head_ref="${2:-HEAD}"
  local -a charts

  if [[ -n "${base_ref}" ]]; then
    mapfile -t charts < <("${REPO_ROOT}/scripts/changed-charts.sh" "${base_ref}" "${head_ref}")
  else
    mapfile -t charts < <("${REPO_ROOT}/scripts/list-charts.sh")
  fi

  for chart_dir in "${charts[@]}"; do
    release_chart "${chart_dir}"
  done
}

main "$@"

