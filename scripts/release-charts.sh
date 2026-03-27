#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OWNER="${GITHUB_REPOSITORY_OWNER:-joejulian}"
OCI_REPO="oci://ghcr.io/${OWNER}/charts"
DIST_DIR="${REPO_ROOT}/.dist"

mkdir -p "${DIST_DIR}"
"${REPO_ROOT}/scripts/setup-helm-repos.sh"

chart_version_published() {
  local chart_name="$1"
  local version="$2"

  helm show chart "${OCI_REPO}/${chart_name}" --version "${version}" >/dev/null 2>&1
}

github_release_exists() {
  local tag="$1"

  gh release view "${tag}" >/dev/null 2>&1
}

release_chart() {
  local chart_dir="$1"
  local chart_name version package tag needs_package

  chart_name="$(basename "${chart_dir}")"
  version="$(helm show chart "${chart_dir}" | awk '/^version:/ {print $2}')"
  tag="${chart_name}-${version}"
  needs_package=1

  if chart_version_published "${chart_name}" "${version}"; then
    echo "Chart ${chart_name} ${version} is already published"
    needs_package=0
  fi

  if [[ "${needs_package}" -eq 1 ]] || ! github_release_exists "${tag}"; then
    if grep -q '^dependencies:' "${chart_dir}/Chart.yaml" 2>/dev/null; then
      helm dependency build "${chart_dir}"
    fi

    package="$(helm package "${chart_dir}" -d "${DIST_DIR}" | awk '{print $NF}')"
  else
    package="${DIST_DIR}/${chart_name}-${version}.tgz"
  fi

  if [[ "${needs_package}" -eq 1 ]]; then
    helm push "${package}" "${OCI_REPO}"
    python3 "${REPO_ROOT}/scripts/verify-chart-package-public.py" \
      "${chart_name}" \
      --token "${GHCR_PACKAGE_TOKEN}"
  fi

  if ! git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
    git tag -a "${tag}" -m "Release ${chart_name} ${version}"
  fi

  if ! github_release_exists "${tag}"; then
    gh release create "${tag}" "${package}" --title "${chart_name} ${version}" --notes "Automated release for ${chart_name} ${version}."
  fi
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
