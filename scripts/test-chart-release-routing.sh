#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_SCRIPT="${REPO_ROOT}/scripts/release-charts.sh"
REPAIR_RELEASE_SCRIPT="${REPO_ROOT}/scripts/repair-chart-releases.sh"

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

push_attempts=0
helm() {
  push_attempts=$((push_attempts + 1))
  [[ "${push_attempts}" -ge 3 ]]
}
sleep() {
  :
}

push_chart_package vault.tgz oci://ghcr.io/heist-crew/casino-charts
assert_equal "3" "${push_attempts}"

# A remote availability probe can fail transiently. Each release operation must
# use one snapshot of remote state so a later probe cannot request publication
# after packaging was skipped based on an earlier successful probe.
(
  # shellcheck source=scripts/repair-chart-releases.sh
  source "${REPAIR_RELEASE_SCRIPT}"

  chart_checks=0
  release_checks=0

  chart_version_published() {
    chart_checks=$((chart_checks + 1))
    [[ "${chart_checks}" -eq 1 ]]
  }
  github_release_exists() {
    release_checks=$((release_checks + 1))
    return 0
  }
  git() {
    return 0
  }
  package_chart() {
    echo "repair unexpectedly packaged after a successful registry probe" >&2
    return 1
  }
  push_chart_package() {
    echo "repair unexpectedly published after a successful registry probe" >&2
    return 1
  }

  ensure_version heist-vault 1.2.3 HEAD
  assert_equal "1" "${chart_checks}"
  assert_equal "1" "${release_checks}"
)

(
  # shellcheck source=scripts/release-charts.sh
  source "${RELEASE_SCRIPT}"

  chart_checks=0
  release_checks=0

  helm() {
    printf '%s\n' 'version: 1.2.3'
  }
  chart_version_published() {
    chart_checks=$((chart_checks + 1))
    [[ "${chart_checks}" -eq 1 ]]
  }
  github_release_exists() {
    release_checks=$((release_checks + 1))
    [[ "${release_checks}" -eq 1 ]]
  }
  git() {
    return 0
  }
  gh() {
    echo "release unexpectedly recreated after a successful GitHub probe" >&2
    return 1
  }
  push_chart_package() {
    echo "release unexpectedly published after a successful registry probe" >&2
    return 1
  }

  release_chart /fixture/heist-vault
  assert_equal "1" "${chart_checks}"
  assert_equal "1" "${release_checks}"
)

echo "Chart release routing tests passed"
