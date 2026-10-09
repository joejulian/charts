{{- define "stable-diffusion.name" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- define "stable-diffusion.selector" -}}
app.kubernetes.io/name: stable-diffusion
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
{{- define "stable-diffusion.labels" -}}
{{ include "stable-diffusion.selector" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}
