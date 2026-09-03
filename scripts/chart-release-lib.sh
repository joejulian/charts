#!/usr/bin/env bash

chart_oci_repository() {
  local owner="${GITHUB_REPOSITORY_OWNER:-joejulian}"
  local package_prefix="${CHART_OCI_PACKAGE_PREFIX:-helm-charts}"

  printf 'oci://ghcr.io/%s/%s\n' "${owner}" "${package_prefix}"
}

chart_package_prefix() {
  local repository="$1"
  local owner="${GITHUB_REPOSITORY_OWNER:-joejulian}"

  printf '%s\n' "${repository#oci://ghcr.io/"${owner}"/}"
}
