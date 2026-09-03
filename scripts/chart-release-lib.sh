#!/usr/bin/env bash

chart_oci_repository() {
  local chart_name="$1"
  local owner="${GITHUB_REPOSITORY_OWNER:-joejulian}"

  case "${chart_name}" in
    justmount | mosquitto)
      printf 'oci://ghcr.io/%s/helm-charts\n' "${owner}"
      ;;
    *)
      printf 'oci://ghcr.io/%s/charts\n' "${owner}"
      ;;
  esac
}

chart_package_prefix() {
  local repository="$1"
  local owner="${GITHUB_REPOSITORY_OWNER:-joejulian}"

  printf '%s\n' "${repository#oci://ghcr.io/"${owner}"/}"
}
