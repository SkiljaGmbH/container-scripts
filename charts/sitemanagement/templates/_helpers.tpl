{{/*
Expand the name of the chart.
*/}}
{{- define "site-management-tool.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "site-management-tool.fullname" -}}
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

{{/*
Chart name and version.
*/}}
{{- define "site-management-tool.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "site-management-tool.labels" -}}
helm.sh/chart: {{ include "site-management-tool.chart" . }}
{{ include "site-management-tool.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Selector labels
*/}}
{{- define "site-management-tool.selectorLabels" -}}
app.kubernetes.io/name: {{ include "site-management-tool.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Pick a per-module override value, falling back to the shared global value when
the module-level field is left as an empty string "".
Usage: {{ include "site-management-tool.pick" (dict "override" .Values.modules.x.server "fallback" .Values.global.database.server) }}
*/}}
{{- define "site-management-tool.pick" -}}
{{- if ne (.override | toString) "" -}}
{{- .override -}}
{{- else -}}
{{- .fallback -}}
{{- end -}}
{{- end -}}
