#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"${REPO_ROOT}/scripts/check-image-repositories.sh"
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

assert_cyrus_imap_ready() {
  local namespace="$1"
  local endpoint_ip=""

  for _ in {1..30}; do
    endpoint_ip="$(kubectl -n "${namespace}" get endpoints cyrus-imap -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || true)"
    if [[ -n "${endpoint_ip}" ]]; then
      return 0
    fi
    sleep 2
  done

  echo "cyrus-imap service has no ready endpoints in namespace ${namespace}" >&2
  return 1
}

assert_cyrus_imap_mount_guard() {
  local namespace="$1"
  local pod

  pod="$(kubectl -n "${namespace}" get pods \
    -l app.kubernetes.io/name=cyrus-imap \
    --field-selector=status.phase=Running \
    --sort-by=.metadata.creationTimestamp \
    -o name | tail -n 1)"
  if [[ -z "${pod}" ]]; then
    echo "cyrus-imap has no running pod in namespace ${namespace}" >&2
    return 1
  fi

  kubectl -n "${namespace}" exec "${pod}" -c cyrus-imap -- \
    /bin/sh -ec '/usr/sbin/mountpoint -q /data/imap_db/socket
/usr/sbin/ss -H -lnt "sport = :143" | /usr/bin/grep -q .'
}

hostpath_pv_remediator_job_manifest() {
  local namespace="$1"
  local node="$2"
  local repair_service_account="$3"
  local incident_id="$4"

  cat <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: hostpath-pv-remediator-${incident_id}
  namespace: ${namespace}
  labels:
    app.kubernetes.io/managed-by: hostpath-pv-remediator
    hostpath-pv-remediator/incident-id: ${incident_id}
  annotations:
    hostpath-pv-remediator/node-name: ${node}
spec:
  backoffLimit: 0
  completions: 1
  parallelism: 1
  activeDeadlineSeconds: 600
  ttlSecondsAfterFinished: 86400
  podReplacementPolicy: Failed
  template:
    metadata:
      labels:
        app.kubernetes.io/managed-by: hostpath-pv-remediator
        hostpath-pv-remediator/incident-id: ${incident_id}
      annotations:
        hostpath-pv-remediator/node-name: ${node}
    spec:
      nodeName: ${node}
      hostPID: true
      restartPolicy: Never
      serviceAccountName: ${repair_service_account}
      automountServiceAccountToken: false
      enableServiceLinks: false
      terminationGracePeriodSeconds: 5
      tolerations:
        - operator: Exists
      containers:
        - name: repair
          image: registry.k8s.io/e2e-test-images/agnhost@sha256:1c5d47ecd9c4fca235ec0eeb9af0c39d8dd981ae703805a1f23676a9bf47c3bb
          imagePullPolicy: IfNotPresent
          args:
            - repair
            - --incident-id=${incident_id}
            - --mount-target=/tmp/hostpath_pv
            - --expected-fstype=fuse.example
            - --expected-source=example.invalid:/volume
            - --systemd-unit=tmp-hostpath_pv.mount
            - --waiting-threshold=8
            - --verify-timeout=5m0s
            - --poll-interval=5s
            - --nsenter-path=/usr/bin/nsenter
            - --fuse-root=/host-sys/fs/fuse/connections
            - --state-dir=/host-state
          securityContext:
            privileged: true
            allowPrivilegeEscalation: true
            readOnlyRootFilesystem: true
            runAsUser: 0
            seccompProfile:
              type: Unconfined
          volumeMounts:
            - name: fuse-connections
              mountPath: /host-sys/fs/fuse/connections
            - name: host-state
              mountPath: /host-state
      volumes:
        - name: fuse-connections
          hostPath:
            path: /sys/fs/fuse/connections
            type: Directory
        - name: host-state
          hostPath:
            path: /var/lib/hostpath-pv-remediator
            type: DirectoryOrCreate
EOF
}

assert_hostpath_pv_remediator_job_lifecycle() (
  local namespace="$1"
  local controller_user="$2"
  local node="$3"
  local repair_service_account="$4"
  local incident_id="$5"
  local job_name="hostpath-pv-remediator-${incident_id}"
  local pod_name=""

  trap 'kubectl -n "${namespace}" delete job "${job_name}" --ignore-not-found=true --wait=true >/dev/null 2>&1 || true' EXIT

  hostpath_pv_remediator_job_manifest \
    "${namespace}" "${node}" "${repair_service_account}" "${incident_id}" |
    kubectl --as="${controller_user}" create -f -

  for _ in {1..60}; do
    pod_name="$(kubectl -n "${namespace}" get pods \
      -l "hostpath-pv-remediator/incident-id=${incident_id}" \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
    [[ -z "${pod_name}" ]] || break
    sleep 1
  done
  if [[ -z "${pod_name}" ]]; then
    echo "hostpath-pv-remediator exact Job did not produce a child Pod" >&2
    kubectl -n "${namespace}" describe job "${job_name}" >&2 || true
    return 1
  fi

  kubectl -n "${namespace}" wait --for=condition=Failed "job/${job_name}" --timeout=2m
  if [[ "$(kubectl -n "${namespace}" get pod "${pod_name}" -o json | jq '(.metadata.finalizers // []) | length')" -ne 0 ]]; then
    echo "hostpath-pv-remediator Job controller could not remove the child Pod tracking finalizer" >&2
    return 1
  fi
)

assert_hostpath_pv_remediator_admission() {
  local namespace="$1"
  local release_name="$2"
  local controller_service_account
  local controller_user
  local controller_pod
  local denied_output
  local binding_count
  local incident_id="deadbeef01234567"
  local node
  local policy_count
  local repair_service_account

  controller_service_account="$(kubectl -n "${namespace}" get deployment "${release_name}" \
    -o jsonpath='{.spec.template.spec.serviceAccountName}')"
  controller_user="system:serviceaccount:${namespace}:${controller_service_account}"
  repair_service_account="$(kubectl -n "${namespace}" get serviceaccounts \
    -l app.kubernetes.io/component=repair \
    -o jsonpath='{.items[0].metadata.name}')"
  node="$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')"

  kubectl --as="${controller_user}" annotate node "${node}" \
    hostpath-pv-remediator/phase=Observed \
    --overwrite --dry-run=server >/dev/null

  if kubectl --as="${controller_user}" annotate node "${node}" \
    hostpath-pv-remediator/approved-incident=abcdef0123456789 \
    --overwrite --dry-run=server >/dev/null 2>&1; then
    echo "hostpath-pv-remediator controller could self-approve an incident" >&2
    return 1
  fi

  policy_count="$(kubectl get validatingadmissionpolicies \
    -l "app.kubernetes.io/instance=${release_name}" -o name | wc -l)"
  if [[ "${policy_count}" -ne 4 ]]; then
    echo "hostpath-pv-remediator expected four admission policies, found ${policy_count}" >&2
    return 1
  fi
  binding_count="$(kubectl get validatingadmissionpolicybindings \
    -l "app.kubernetes.io/instance=${release_name}" -o name | wc -l)"
  if [[ "${binding_count}" -ne 4 ]]; then
    echo "hostpath-pv-remediator expected four admission policy bindings, found ${binding_count}" >&2
    return 1
  fi

  if denied_output="$(kubectl -n "${namespace}" run heist-privileged-init \
    --image=registry.k8s.io/e2e-test-images/agnhost:2.53 \
    --restart=Never \
    --overrides='{"spec":{"initContainers":[{"name":"basher-tarr","image":"registry.k8s.io/e2e-test-images/agnhost:2.53","securityContext":{"privileged":true}}]}}' \
    --dry-run=server 2>&1)"; then
    echo "hostpath-pv-remediator accepted a directly created privileged init Pod" >&2
    return 1
  fi
  if ! grep -Fq 'Only the configured Kubernetes Job controller may create a repair Pod.' <<<"${denied_output}"; then
    echo "hostpath-pv-remediator rejected the privileged init Pod for an unexpected reason: ${denied_output}" >&2
    return 1
  fi

  controller_pod="$(kubectl -n "${namespace}" get pods \
    -l app.kubernetes.io/component=controller \
    -o jsonpath='{.items[0].metadata.name}')"
  if denied_output="$(kubectl -n "${namespace}" exec "${controller_pod}" -- /bin/true 2>&1)"; then
    echo "hostpath-pv-remediator allowed interactive Pod exec" >&2
    return 1
  fi
  if ! grep -Fq 'Interactive Pod access is forbidden in the remediation namespace.' <<<"${denied_output}"; then
    echo "hostpath-pv-remediator rejected Pod exec for an unexpected reason: ${denied_output}" >&2
    return 1
  fi

  assert_hostpath_pv_remediator_job_lifecycle \
    "${namespace}" "${controller_user}" "${node}" "${repair_service_account}" "${incident_id}"

  if denied_output="$(hostpath_pv_remediator_job_manifest \
    "${namespace}" "${node}" "${repair_service_account}" "ba5eba1101234567" |
    kubectl create --dry-run=client -o json -f - |
    jq '.spec.backoffLimit = 1' |
    kubectl --as="${controller_user}" create --dry-run=server -f - 2>&1)"; then
    echo "hostpath-pv-remediator accepted a retry-enabled repair Job" >&2
    return 1
  fi
  if ! grep -Fq 'retry, replacement, completion, concurrency, deadline, and TTL contract is immutable' <<<"${denied_output}"; then
    echo "hostpath-pv-remediator rejected the retry mutation for an unexpected reason: ${denied_output}" >&2
    return 1
  fi
}

assert_hostpath_pv_remediator_render_guards() {
  local chart_dir="$1"
  local values_file="$2"
  local digest="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  local -a values_args=()

  if [[ -f "${values_file}" ]]; then
    values_args=(-f "${values_file}")
  fi

  if helm template heist-initial "${chart_dir}" "${values_args[@]}" \
    --set remediation.enabled=true \
    --set "image.digest=${digest}" >/dev/null 2>&1; then
    echo "hostpath-pv-remediator allowed remediation during its initial install" >&2
    return 1
  fi

  if helm template --is-upgrade heist-upgrade "${chart_dir}" "${values_args[@]}" \
    --set remediation.enabled=true \
    --set admissionPolicy.enabled=false \
    --set "image.digest=${digest}" >/dev/null 2>&1; then
    echo "hostpath-pv-remediator allowed active remediation without admission policies" >&2
    return 1
  fi

  helm template --is-upgrade heist-upgrade "${chart_dir}" "${values_args[@]}" \
    --set remediation.enabled=true \
    --set "image.digest=${digest}" >/dev/null
}

assert_home_assistant_image_prepull_render() {
  local chart_dir="$1"
  local chart_app_version
  local fixture="${REPO_ROOT}/ci/fixtures/home-assistant/prepull-values.yaml"
  local default_image_render
  local install_render
  local upgrade_render

  install_render="$(helm template heist-initial "${chart_dir}" --values "${fixture}")"
  if grep -Fq '"helm.sh/hook": pre-upgrade' <<<"${install_render}"; then
    echo "home-assistant rendered its image pre-pull hook during initial install" >&2
    return 1
  fi

  upgrade_render="$(helm template --is-upgrade heist-upgrade "${chart_dir}" --values "${fixture}")"
  for expected in \
    'kind: Job' \
    'name: heist-upgrade-image-prepull' \
    '"helm.sh/hook": pre-upgrade' \
    '"helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded' \
    'activeDeadlineSeconds: 4500' \
    'example.invalid/usb-node: "true"' \
    'ghcr.io/joejulian/container-images/home-assistant:heist-movie@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; do
    if ! grep -Fq "${expected}" <<<"${upgrade_render}"; then
      echo "home-assistant image pre-pull render is missing: ${expected}" >&2
      return 1
    fi
  done

  chart_app_version="$(python3 "${REPO_ROOT}/scripts/chart_yaml.py" json --file "${chart_dir}/Chart.yaml" | jq -r .appVersion)"
  default_image_render="$(helm template --is-upgrade heist-default "${chart_dir}" --set imagePrePull.enabled=true)"
  if ! grep -Fq "ghcr.io/joejulian/container-images/home-assistant:${chart_app_version}" \
    <<<"${default_image_render}"; then
    echo "home-assistant image pre-pull did not default to chart.appVersion" >&2
    return 1
  fi
}

run_chart_tests() {
  local chart_name="$1"
  local release_name="$2"
  local namespace="$3"

  case "${chart_name}" in
    cyrus-imap)
      assert_cyrus_imap_ready "${namespace}"
      assert_cyrus_imap_mount_guard "${namespace}"
      ;;
    hostpath-pv-remediator)
      helm test "${release_name}" -n "${namespace}" --timeout 5m
      assert_hostpath_pv_remediator_admission "${namespace}" "${release_name}"
      ;;
    *)
      helm test "${release_name}" -n "${namespace}" --timeout 5m
      ;;
  esac
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
    unifi-cam-proxy)
      kubectl -n "${namespace}" create secret generic unifi-cam-proxy-env \
        --from-literal=PROTECT_NVR_HOST=protect.example.invalid \
        --from-literal=PROTECT_NVR_USERNAME=test-user \
        --from-literal=PROTECT_NVR_PASSWORD=test-password \
        --from-literal=PROTECT_TOKEN=test-token \
        --from-literal=CAMERA_DISPLAY_IP=192.0.2.10 \
        --from-literal=CAMERA_NAME=front-door \
        --from-literal=CAMERA_MODEL=UVC_G4_Dome \
        --from-literal=CAMERA_MAC=AA:BB:CC:DD:EE:FF \
        --dry-run=client -o yaml | kubectl apply -f -
      kubectl -n "${namespace}" create secret generic unifi-cam-proxy-identity \
        --from-file=client.pem="${REPO_ROOT}/ci/fixtures/unifi-cam-proxy/client.pem" \
        --dry-run=client -o yaml | kubectl apply -f -
      ;;
    onstar2mqtt)
      if [[ -n "${ONSTAR2MQTT_TEST_SECRET:-}" ]]; then
        printf '%s\n' "${ONSTAR2MQTT_TEST_SECRET}" | kubectl -n "${namespace}" apply -f -
      fi
      ;;
  esac
}

setup_image_pull_secret() {
  local namespace="$1"

  if [[ -z "${GHCR_PULL_USERNAME:-}" || -z "${GHCR_PULL_PASSWORD:-}" ]]; then
    return
  fi

  kubectl -n "${namespace}" create secret docker-registry ghcr-auth \
    --docker-server=ghcr.io \
    --docker-username="${GHCR_PULL_USERNAME}" \
    --docker-password="${GHCR_PULL_PASSWORD}" \
    --dry-run=client -o yaml | kubectl apply -f -
}

test_chart() {
  local chart_dir="$1"
  local chart_name
  local namespace
  local release_name
  local values_file
  local -a helm_args
  local -a previous_helm_args

  chart_name="$(basename "${chart_dir}")"
  namespace="ci-${chart_name}"
  release_name="${chart_name}"
  values_file="${REPO_ROOT}/ci/values/${chart_name}.yaml"
  helm_args=(upgrade --install "${chart_name}" "${chart_dir}" -n "${namespace}" --create-namespace --wait --timeout 10m)

  if [[ "${chart_name}" == "onstar2mqtt" && -z "${ONSTAR2MQTT_TEST_SECRET:-}" ]]; then
    echo "Skipping ${chart_name}; set ONSTAR2MQTT_TEST_SECRET to enable credentialed e2e coverage."
    return
  fi

  if [[ -f "${values_file}" ]]; then
    helm_args+=(-f "${values_file}")
  fi

  build_dependencies "${chart_dir}"
  if [[ "${chart_name}" == "hostpath-pv-remediator" ]]; then
    assert_hostpath_pv_remediator_render_guards "${chart_dir}" "${values_file}"
  fi
  if [[ "${chart_name}" == "home-assistant" ]]; then
    assert_home_assistant_image_prepull_render "${chart_dir}"
  fi
  kubectl get namespace "${namespace}" >/dev/null 2>&1 || kubectl create namespace "${namespace}"
  setup_image_pull_secret "${namespace}"
  setup_chart_fixtures "${chart_name}" "${namespace}"

  if [[ "${chart_name}" == "cyrus-imap" ]]; then
    previous_helm_args=(upgrade --install "${release_name}" \
      oci://ghcr.io/joejulian/charts/cyrus-imap \
      --version 0.1.4 -n "${namespace}" --wait --timeout 10m)
    if [[ -f "${values_file}" ]]; then
      previous_helm_args+=(-f "${values_file}")
    fi
    helm "${previous_helm_args[@]}"
  fi

  helm "${helm_args[@]}"
  wait_for_workloads "${namespace}"

  run_chart_tests "${chart_name}" "${release_name}" "${namespace}"

  helm "${helm_args[@]}"
  wait_for_workloads "${namespace}"
  run_chart_tests "${chart_name}" "${release_name}" "${namespace}"
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
