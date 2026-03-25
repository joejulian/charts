#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"${REPO_ROOT}/scripts/setup-helm-repos.sh"

build_dependencies() {
  local chart_dir="$1"
  if grep -q '^dependencies:' "${chart_dir}/Chart.yaml" 2>/dev/null; then
    helm dependency build "${chart_dir}"
  fi
}

wait_for_workloads() {
  local namespace="$1"
  local resource

  while read -r resource; do
    [[ -z "${resource}" ]] || kubectl -n "${namespace}" rollout status "${resource}" --timeout=5m
  done < <(kubectl -n "${namespace}" get deployment,statefulset,daemonset -o name 2>/dev/null || true)
}

setup_chart_fixtures() {
  local chart_name="$1"
  local namespace="$2"

  case "${chart_name}" in
    postfix)
      kubectl -n "${namespace}" create configmap postfix \
        --from-file=main.cf="${REPO_ROOT}/ci/fixtures/postfix/main.cf" \
        --from-file=master.cf="${REPO_ROOT}/ci/fixtures/postfix/master.cf" \
        --dry-run=client -o yaml | kubectl apply -f -
      ;;
    onstar2mqtt)
      if [[ -n "${ONSTAR2MQTT_TEST_SECRET:-}" ]]; then
        printf '%s\n' "${ONSTAR2MQTT_TEST_SECRET}" | kubectl -n "${namespace}" apply -f -
      fi
      ;;
  esac
}

test_chart() {
  local chart_dir="$1"
  local chart_name
  local namespace
  local release_name
  local values_file
  local -a helm_args

  chart_name="$(basename "${chart_dir}")"
  namespace="ci-${chart_name}"
  release_name="${namespace}"
  values_file="${REPO_ROOT}/ci/values/${chart_name}.yaml"
  helm_args=(upgrade --install "${release_name}" "${chart_dir}" -n "${namespace}" --create-namespace --wait --timeout 10m)

  if [[ "${chart_name}" == "onstar2mqtt" && -z "${ONSTAR2MQTT_TEST_SECRET:-}" ]]; then
    echo "Skipping ${chart_name}; set ONSTAR2MQTT_TEST_SECRET to enable credentialed e2e coverage."
    return
  fi

  if [[ -f "${values_file}" ]]; then
    helm_args+=(-f "${values_file}")
  fi

  build_dependencies "${chart_dir}"
  kubectl get namespace "${namespace}" >/dev/null 2>&1 || kubectl create namespace "${namespace}"
  setup_chart_fixtures "${chart_name}" "${namespace}"

  helm "${helm_args[@]}"
  wait_for_workloads "${namespace}"

  helm test "${release_name}" -n "${namespace}" --timeout 5m

  helm "${helm_args[@]}"
  wait_for_workloads "${namespace}"
  helm test "${release_name}" -n "${namespace}" --timeout 5m
}

main() {
  local chart_dir
  local -a charts

  if [[ "$#" -gt 0 ]]; then
    charts=("$@")
  else
    mapfile -t charts < <("${REPO_ROOT}/scripts/list-charts.sh")
  fi

  for chart_dir in "${charts[@]}"; do
    echo "== Testing ${chart_dir} =="
    test_chart "${chart_dir}"
  done
}

main "$@"
