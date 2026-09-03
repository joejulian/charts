#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# shellcheck source=scripts/chart-version-lib.sh
source "${REPO_ROOT}/scripts/chart-version-lib.sh"

fail() {
  echo "$*" >&2
  exit 1
}

assert_level() {
  local expected="$1"
  local base="$2"
  local current="$3"
  local actual

  actual="$(version_change_level "${base}" "${current}")"
  [[ "${actual}" == "${expected}" ]] || fail "${base} -> ${current}: expected level ${expected}, got ${actual}"
}

assert_level 0 4.0.19.3009 4.0.19.3009
assert_level 1 4.0.17.2969 4.0.19.3009
assert_level 1 latest stable
assert_level 1 v1.2.3 v1.2.4
assert_level 2 2026.3.4 2026.6.4
assert_level 3 1.9.9 2.0.0

tmp_root="$(mktemp -d)"
trap 'rm -r "${tmp_root}"' EXIT

new_fixture() {
  local fixture="$1"
  local app_version="$2"
  local chart_version="$3"
  local fixture_root="${tmp_root}/${fixture}"

  mkdir -p "${fixture_root}/charts/heist-vault" "${fixture_root}/scripts"
  cp \
    "${REPO_ROOT}/scripts/bump-chart.sh" \
    "${REPO_ROOT}/scripts/changed-charts.sh" \
    "${REPO_ROOT}/scripts/chart-version-lib.sh" \
    "${REPO_ROOT}/scripts/chart_yaml.py" \
    "${REPO_ROOT}/scripts/check-chart-version-bumps.sh" \
    "${fixture_root}/scripts/"
  printf '%s\n' \
    'apiVersion: v2' \
    "appVersion: ${app_version}" \
    'name: heist-vault' \
    'type: application' \
    "version: ${chart_version}" \
    > "${fixture_root}/charts/heist-vault/Chart.yaml"
  printf '%s\n' \
    'image:' \
    '  repository: ghcr.io/heist-movie/oceans-eleven' \
    '  tag: 1.0.0' \
    > "${fixture_root}/charts/heist-vault/values.yaml"
  git -C "${fixture_root}" init -q
  git -C "${fixture_root}" config user.name "Danny Ocean"
  git -C "${fixture_root}" config user.email "danny.ocean@example.invalid"
  git -C "${fixture_root}" add .
  git -C "${fixture_root}" commit -qm "test: establish Bellagio vault chart"
  printf '%s\n' "${fixture_root}"
}

four_part_root="$(new_fixture four-part 4.0.17.2969 1.12.0)"
sed -i 's/4\.0\.17\.2969/4.0.19.3009/' "${four_part_root}/charts/heist-vault/Chart.yaml"
"${four_part_root}/scripts/bump-chart.sh"
four_part_version="$(python3 "${four_part_root}/scripts/chart_yaml.py" json --file "${four_part_root}/charts/heist-vault/Chart.yaml" | jq -r .version)"
[[ "${four_part_version}" == "1.12.1" ]] || fail "four-part appVersion update did not bump the chart patch"

values_root="$(new_fixture values-change 1.2.3 2.4.6)"
sed -i 's/tag: 1\.0\.0/tag: 1.0.1/' "${values_root}/charts/heist-vault/values.yaml"
"${values_root}/scripts/bump-chart.sh"
values_version="$(python3 "${values_root}/scripts/chart_yaml.py" json --file "${values_root}/charts/heist-vault/Chart.yaml" | jq -r .version)"
[[ "${values_version}" == "2.4.7" ]] || fail "values update did not bump the chart patch"

guard_root="$(new_fixture guard 1.2.3 3.5.7)"
guard_base="$(git -C "${guard_root}" rev-parse HEAD)"
sed -i 's/tag: 1\.0\.0/tag: 1.0.1/' "${guard_root}/charts/heist-vault/values.yaml"
git -C "${guard_root}" add charts/heist-vault/values.yaml
git -C "${guard_root}" commit -qm "test: change Rusty Ryan image without chart bump"
if bash "${guard_root}/scripts/check-chart-version-bumps.sh" "${guard_base}" HEAD >"${tmp_root}/guard-output" 2>&1; then
  fail "chart version guard accepted changed packaged content without a chart bump"
fi
if ! grep -q 'packaged chart content changed' "${tmp_root}/guard-output"; then
  sed -n '1,120p' "${tmp_root}/guard-output" >&2
  fail "chart version guard failed without the expected diagnostic"
fi

assert_guard_result() {
  local expected="$1"
  local fixture="$2"
  local base_app_version="$3"
  local head_app_version="$4"
  local base_chart_version="$5"
  local head_chart_version="$6"
  local fixture_root fixture_base

  fixture_root="$(new_fixture "${fixture}" "${base_app_version}" "${base_chart_version}")"
  fixture_base="$(git -C "${fixture_root}" rev-parse HEAD)"
  sed -i "s/appVersion: ${base_app_version}/appVersion: ${head_app_version}/" "${fixture_root}/charts/heist-vault/Chart.yaml"
  sed -i "s/version: ${base_chart_version}/version: ${head_chart_version}/" "${fixture_root}/charts/heist-vault/Chart.yaml"
  sed -i 's/tag: 1\.0\.0/tag: 1.0.1/' "${fixture_root}/charts/heist-vault/values.yaml"
  git -C "${fixture_root}" add charts/heist-vault
  git -C "${fixture_root}" commit -qm "test: update the Bellagio vault chart"

  if bash "${fixture_root}/scripts/check-chart-version-bumps.sh" "${fixture_base}" HEAD >"${tmp_root}/${fixture}-output" 2>&1; then
    [[ "${expected}" == pass ]] || fail "chart version guard accepted misaligned ${fixture} versions"
  else
    [[ "${expected}" == fail ]] || {
      sed -n '1,120p' "${tmp_root}/${fixture}-output" >&2
      fail "chart version guard rejected aligned ${fixture} versions"
    }
  fi
}

assert_guard_result pass feature-choice 1.2.3 1.2.3 3.5.7 3.6.0
assert_guard_result pass patch-aligned 1.2.3 1.2.4 3.5.7 3.5.8
assert_guard_result pass minor-aligned 1.2.3 1.3.0 3.5.7 3.6.0
assert_guard_result pass major-aligned 1.2.3 2.0.0 3.5.7 4.0.0
assert_guard_result fail minor-misaligned 1.2.3 1.3.0 3.5.7 3.5.8
assert_guard_result fail patch-misaligned 1.2.3 1.2.4 3.5.7 3.6.0
