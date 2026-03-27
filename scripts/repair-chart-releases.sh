#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OWNER="${GITHUB_REPOSITORY_OWNER:-joejulian}"
OCI_REPO="oci://ghcr.io/${OWNER}/charts"
DIST_DIR="${REPO_ROOT}/.dist"
TMP_ROOT="/tmp/jjulian/chart-release-repair"

mkdir -p "${DIST_DIR}" "${TMP_ROOT}"
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

remote_tag_exists() {
  local tag="$1"

  git ls-remote --exit-code --tags origin "refs/tags/${tag}" >/dev/null 2>&1
}

ensure_dependencies() {
  local chart_dir="$1"

  if grep -q '^dependencies:' "${chart_dir}/Chart.yaml" 2>/dev/null; then
    helm dependency build "${chart_dir}"
  fi
}

package_chart() {
  local chart_dir="$1"

  ensure_dependencies "${chart_dir}"
  helm package "${chart_dir}" -d "${DIST_DIR}" | awk '{print $NF}'
}

extract_chart_at_ref() {
  local ref="$1"
  local chart_name="$2"
  local extract_root

  extract_root="$(mktemp -d "${TMP_ROOT}/${chart_name}-${ref//\//-}-XXXXXX")"
  git -C "${REPO_ROOT}" archive --format=tar "${ref}" "charts/${chart_name}" | tar -xf - -C "${extract_root}"
  printf '%s\n' "${extract_root}/charts/${chart_name}"
}

ensure_version() {
  local chart_name="$1"
  local version="$2"
  local ref="$3"
  local tag="${chart_name}-${version}"
  local package chart_dir cleanup_dir

  package="${DIST_DIR}/${chart_name}-${version}.tgz"
  chart_dir="${REPO_ROOT}/charts/${chart_name}"
  cleanup_dir=""

  if [[ "${ref}" != "HEAD" ]]; then
    chart_dir="$(extract_chart_at_ref "${ref}" "${chart_name}")"
    cleanup_dir="$(dirname "$(dirname "${chart_dir}")")"
  fi

  if ! chart_version_published "${chart_name}" "${version}" || ! github_release_exists "${tag}"; then
    package="$(package_chart "${chart_dir}")"
  fi

  if ! chart_version_published "${chart_name}" "${version}"; then
    echo "Publishing ${chart_name} ${version} from ${ref}"
    helm push "${package}" "${OCI_REPO}"
  fi

  if ! git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
    git tag -a "${tag}" -m "Release ${chart_name} ${version}"
  fi

  if ! github_release_exists "${tag}"; then
    if ! remote_tag_exists "${tag}"; then
      git push origin "refs/tags/${tag}"
    fi
    echo "Creating GitHub release ${tag}"
    gh release create "${tag}" "${package}" --title "${chart_name} ${version}" --notes "Automated release for ${chart_name} ${version}."
  fi

  if [[ -n "${cleanup_dir}" ]]; then
    rm -rf "${cleanup_dir}"
  fi
}

collect_versions() {
  local chart_name="$1"
  local current_version
  declare -A refs=()
  local ref version

  while IFS= read -r ref; do
    version="${ref#${chart_name}-}"
    refs["${version}"]="${ref}"
  done < <(git -C "${REPO_ROOT}" tag -l "${chart_name}-*")

  current_version="$(python3 "${REPO_ROOT}/scripts/chart_yaml.py" json --file "${REPO_ROOT}/charts/${chart_name}/Chart.yaml" | python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])')"
  if [[ -n "${current_version}" && -z "${refs[${current_version}]:-}" ]]; then
    refs["${current_version}"]="HEAD"
  fi

  for version in "${!refs[@]}"; do
    printf '%s\t%s\n' "${version}" "${refs[${version}]}"
  done | sort -V
}

resolve_charts() {
  local mode="${1:-all}"
  shift || true

  case "${mode}" in
    all)
      "${REPO_ROOT}/scripts/list-charts.sh"
      ;;
    changed)
      "${REPO_ROOT}/scripts/changed-charts.sh" "${1:-}" "${2:-HEAD}"
      ;;
    named)
      for chart_name in "$@"; do
        printf '%s/charts/%s\n' "${REPO_ROOT}" "${chart_name}"
      done
      ;;
    *)
      echo "unknown mode: ${mode}" >&2
      return 1
      ;;
  esac
}

main() {
  local mode="all"
  local -a mode_args=()
  local chart_dir chart_name line version ref

  if [[ $# -gt 0 ]]; then
    case "$1" in
      --all)
        mode="all"
        shift
        ;;
      --changed)
        mode="changed"
        mode_args=("${2:-}" "${3:-HEAD}")
        shift 3 || true
        ;;
      --charts)
        mode="named"
        shift
        mode_args=("$@")
        ;;
      *)
        echo "usage: $0 [--all | --changed BASE HEAD | --charts chart ...]" >&2
        return 1
        ;;
    esac
  fi

  while IFS= read -r chart_dir; do
    [[ -n "${chart_dir}" ]] || continue
    chart_name="$(basename "${chart_dir}")"
    while IFS=$'\t' read -r version ref; do
      ensure_version "${chart_name}" "${version}" "${ref}"
    done < <(collect_versions "${chart_name}")
  done < <(resolve_charts "${mode}" "${mode_args[@]}")
}

main "$@"
