{{- define "ha-todo-mcp.name" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- define "ha-todo-mcp.labels" -}}
app.kubernetes.io/name: ha-todo-mcp
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}
{{- define "ha-todo-mcp.selector" -}}
app.kubernetes.io/name: ha-todo-mcp
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
{{- define "ha-todo-mcp.image" -}}
{{ .Values.image.repository }}:{{ default .Chart.AppVersion .Values.image.tag }}
{{- end -}}
