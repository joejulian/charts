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

push_chart_package() {
  local package="$1"
  local repository="$2"
  local attempt delay

  for attempt in 1 2 3 4 5; do
    if helm push "${package}" "${repository}"; then
      return 0
    fi

    if [[ "${attempt}" -eq 5 ]]; then
      echo "Chart push failed after ${attempt} attempts" >&2
      return 1
    fi

    delay=$((attempt * 5))
    echo "Chart push failed; retrying in ${delay}s (${attempt}/5)" >&2
    sleep "${delay}"
  done
}
