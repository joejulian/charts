{{/* Common labels for the Kadalu operator release. */}}
{{- define "kadalu-operator.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: kadalu-operator
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: kadalu
{{- end -}}

{{/* Resolve the operator image, preferring a complete immutable override. */}}
{{- define "kadalu-operator.image" -}}
{{- if .Values.operator.image.fullOverride -}}
{{- .Values.operator.image.fullOverride -}}
{{- else if .Values.operator.image.digest -}}
{{- printf "%s:%s@%s" .Values.operator.image.repository .Values.operator.image.tag .Values.operator.image.digest -}}
{{- else -}}
{{- printf "%s:%s" .Values.operator.image.repository .Values.operator.image.tag -}}
{{- end -}}
{{- end -}}

{{/* Keep annotations make the two-release RBAC handoff non-destructive. */}}
{{- define "kadalu-operator.keepAnnotations" -}}
helm.sh/resource-policy: keep
{{- end -}}
