{{- define "edge-gateway.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "edge-gateway.fullname" -}}
{{- if contains .Chart.Name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "edge-gateway.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{ include "edge-gateway.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: platform-edge
{{- end -}}

{{- define "edge-gateway.selectorLabels" -}}
app.kubernetes.io/name: {{ include "edge-gateway.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "edge-gateway.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "edge-gateway.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/* ConfigMap com o kong.yaml, se algum foi informado. */}}
{{- define "edge-gateway.configMapName" -}}
{{- if .Values.declarativeConfig.existingConfigMap -}}
{{- .Values.declarativeConfig.existingConfigMap -}}
{{- else if .Values.declarativeConfig.inline -}}
{{- printf "%s-declarative" (include "edge-gateway.fullname" .) -}}
{{- end -}}
{{- end -}}
