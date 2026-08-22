{{/* Expand the chart name. */}}
{{- define "hostpath-pv-remediator.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Create a DNS-safe fully qualified release name. */}}
{{- define "hostpath-pv-remediator.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/* Create the chart label. */}}
{{- define "hostpath-pv-remediator.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Common labels. */}}
{{- define "hostpath-pv-remediator.labels" -}}
helm.sh/chart: {{ include "hostpath-pv-remediator.chart" . }}
{{ include "hostpath-pv-remediator.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/* Deployment selector labels. */}}
{{- define "hostpath-pv-remediator.selectorLabels" -}}
app.kubernetes.io/name: {{ include "hostpath-pv-remediator.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* Controller workload selector labels. */}}
{{- define "hostpath-pv-remediator.controllerSelectorLabels" -}}
{{ include "hostpath-pv-remediator.selectorLabels" . }}
app.kubernetes.io/component: controller
{{- end -}}

{{/* Controller ServiceAccount name. */}}
{{- define "hostpath-pv-remediator.serviceAccountName" -}}
{{- default (include "hostpath-pv-remediator.fullname" .) .Values.serviceAccount.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Deliberately unbound repair ServiceAccount name. */}}
{{- define "hostpath-pv-remediator.repairServiceAccountName" -}}
{{- $base := include "hostpath-pv-remediator.fullname" . | trunc 56 | trimSuffix "-" -}}
{{- default (printf "%s-repair" $base) .Values.repairServiceAccount.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Tokenless Helm test ServiceAccount and Pod name. */}}
{{- define "hostpath-pv-remediator.testName" -}}
{{- $base := include "hostpath-pv-remediator.fullname" . | trunc 58 | trimSuffix "-" -}}
{{- printf "%s-test" $base -}}
{{- end -}}

{{/* Fixed controller-runtime leader-election Lease name. */}}
{{- define "hostpath-pv-remediator.leaderElectionLeaseName" -}}
hostpath-pv-remediator-leader-election
{{- end -}}

{{/* Pre-created remediation serialization Lease name. */}}
{{- define "hostpath-pv-remediator.repairLeaseName" -}}
{{- .Values.remediation.leaseName | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Cluster-scoped admission policy name. */}}
{{- define "hostpath-pv-remediator.admissionPolicyName" -}}
{{- $base := include "hostpath-pv-remediator.fullname" . | trunc 52 | trimSuffix "-" -}}
{{- printf "%s-repair-job" $base -}}
{{- end -}}

{{/* Cluster-scoped policy validating the Job controller's generated repair Pod. */}}
{{- define "hostpath-pv-remediator.podAdmissionPolicyName" -}}
{{- $base := include "hostpath-pv-remediator.fullname" . | trunc 52 | trimSuffix "-" -}}
{{- printf "%s-repair-pod" $base -}}
{{- end -}}

{{/* Cluster-scoped policy denying interactive access to Pods in the repair namespace. */}}
{{- define "hostpath-pv-remediator.connectAdmissionPolicyName" -}}
{{- $base := include "hostpath-pv-remediator.fullname" . | trunc 50 | trimSuffix "-" -}}
{{- printf "%s-deny-connect" $base -}}
{{- end -}}

{{/* Cluster-scoped policy restricting controller Node patches. */}}
{{- define "hostpath-pv-remediator.nodeAdmissionPolicyName" -}}
{{- $base := include "hostpath-pv-remediator.fullname" . | trunc 52 | trimSuffix "-" -}}
{{- printf "%s-node-patch" $base -}}
{{- end -}}

{{/* Exact Kubernetes username of the controller ServiceAccount. */}}
{{- define "hostpath-pv-remediator.controllerUsername" -}}
{{- printf "system:serviceaccount:%s:%s" .Release.Namespace (include "hostpath-pv-remediator.serviceAccountName" .) -}}
{{- end -}}

{{/* Resolve the controller and repair image, preferring an immutable digest. */}}
{{- define "hostpath-pv-remediator.image" -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository (default .Chart.AppVersion .Values.image.tag) -}}
{{- end -}}
{{- end -}}

{{/* Resolve the Helm test image. */}}
{{- define "hostpath-pv-remediator.testImage" -}}
{{- if .Values.test.image.digest -}}
{{- printf "%s@%s" .Values.test.image.repository .Values.test.image.digest -}}
{{- else -}}
{{- printf "%s:%s" .Values.test.image.repository .Values.test.image.tag -}}
{{- end -}}
{{- end -}}

{{/* Exact repair executor argument vector produced by the controller, as CEL. */}}
{{- define "hostpath-pv-remediator.repairArgsCEL" -}}
[
  "repair",
  "--incident-id=" + object.metadata.labels['hostpath-pv-remediator/incident-id'],
  {{ printf "--mount-target=%s" .Values.repair.mountTarget | toJson }},
  {{ printf "--expected-fstype=%s" .Values.repair.expectedFSType | toJson }},
  {{ printf "--expected-source=%s" .Values.repair.expectedSource | toJson }},
  {{ printf "--systemd-unit=%s" .Values.repair.systemdUnit | toJson }},
  {{ printf "--waiting-threshold=%v" .Values.repair.waitingThreshold | toJson }},
  {{ printf "--verify-timeout=%s" (duration (printf "%v" .Values.repair.verifyTimeoutSeconds)) | toJson }},
  {{ printf "--poll-interval=%s" (duration (printf "%v" .Values.repair.pollIntervalSeconds)) | toJson }},
  "--nsenter-path=/usr/bin/nsenter",
  "--fuse-root=/host-sys/fs/fuse/connections",
  "--state-dir=/host-state"
]
{{- end -}}

{{/* Refuse active remediation unless the executor image is immutable. */}}
{{- define "hostpath-pv-remediator.validate" -}}
{{- if and .Release.IsInstall .Values.remediation.enabled -}}
{{- fail "the initial install must use remediation.enabled=false; enable remediation only in a verified upgrade" -}}
{{- end -}}
{{- if and .Values.remediation.enabled (not .Values.admissionPolicy.enabled) -}}
{{- fail "admissionPolicy.enabled must remain true when remediation.enabled=true" -}}
{{- end -}}
{{- if and .Values.remediation.enabled (not .Values.image.digest) -}}
{{- fail "image.digest must be a sha256 digest when remediation.enabled=true" -}}
{{- end -}}
{{- if eq (include "hostpath-pv-remediator.serviceAccountName" .) (include "hostpath-pv-remediator.repairServiceAccountName" .) -}}
{{- fail "serviceAccount.name and repairServiceAccount.name must resolve to different names" -}}
{{- end -}}
{{- if eq (include "hostpath-pv-remediator.admissionPolicyName" .) (include "hostpath-pv-remediator.nodeAdmissionPolicyName" .) -}}
{{- fail "repair Job and Node admission policy names must resolve to different names" -}}
{{- end -}}
{{- $jobPolicy := include "hostpath-pv-remediator.admissionPolicyName" . -}}
{{- $podPolicy := include "hostpath-pv-remediator.podAdmissionPolicyName" . -}}
{{- $connectPolicy := include "hostpath-pv-remediator.connectAdmissionPolicyName" . -}}
{{- $nodePolicy := include "hostpath-pv-remediator.nodeAdmissionPolicyName" . -}}
{{- if or (eq $jobPolicy $podPolicy) (eq $jobPolicy $connectPolicy) (eq $jobPolicy $nodePolicy) (eq $podPolicy $connectPolicy) (eq $podPolicy $nodePolicy) (eq $connectPolicy $nodePolicy) -}}
{{- fail "repair Job, repair Pod, deny-connect, and Node admission policy names must resolve to different names" -}}
{{- end -}}
{{- end -}}
