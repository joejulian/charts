#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# shellcheck source=scripts/chart-release-lib.sh
source "${REPO_ROOT}/scripts/chart-release-lib.sh"

assert_equal() {
  local want="$1"
  local got="$2"

  if [[ "${want}" != "${got}" ]]; then
    printf 'want %q, got %q\n' "${want}" "${got}" >&2
    return 1
  fi
}

assert_equal \
  "oci://ghcr.io/joejulian/helm-charts" \
  "$(chart_oci_repository justmount)"
assert_equal \
  "oci://ghcr.io/joejulian/helm-charts" \
  "$(chart_oci_repository mosquitto)"
assert_equal \
  "oci://ghcr.io/joejulian/helm-charts" \
  "$(chart_oci_repository sonarr)"
assert_equal \
  "helm-charts" \
  "$(chart_package_prefix "$(chart_oci_repository justmount)")"

GITHUB_REPOSITORY_OWNER=heist-crew
export GITHUB_REPOSITORY_OWNER
assert_equal \
  "oci://ghcr.io/heist-crew/helm-charts" \
  "$(chart_oci_repository vault)"
assert_equal \
  "helm-charts" \
  "$(chart_package_prefix "$(chart_oci_repository vault)")"

CHART_OCI_PACKAGE_PREFIX=casino-charts
export CHART_OCI_PACKAGE_PREFIX
assert_equal \
  "oci://ghcr.io/heist-crew/casino-charts" \
  "$(chart_oci_repository vault)"

echo "Chart release routing tests passed"
