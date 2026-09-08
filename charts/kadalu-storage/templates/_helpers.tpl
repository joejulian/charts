{{- define "kadalu-storage.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: kadalu-storage
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: kadalu
app.kubernetes.io/component: storage-server
{{- end -}}

{{/* Keep the adopted service account while the old operator release drops it. */}}
{{- define "kadalu-storage.handoffAnnotations" -}}
{{- if .Values.migration.retainDuringOperatorHandoff }}
annotations:
  helm.sh/resource-policy: keep
{{- end }}
{{- end -}}
