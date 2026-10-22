{{/*
Expand the name of the chart.
*/}}
{{- define "classification-monitor.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "classification-monitor.fullname" -}}
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
{{- define "classification-monitor.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "classification-monitor.labels" -}}
helm.sh/chart: {{ include "classification-monitor.chart" . }}
{{ include "classification-monitor.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Selector labels
*/}}
{{- define "classification-monitor.selectorLabels" -}}
app.kubernetes.io/name: {{ include "classification-monitor.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: classification-monitor
{{- end -}}

{{/*
Gateway API mode: "true" renders an HTTPRoute instead of the Ingress.
httpRoute.enabled (true/false) overrides global.gateway.enabled for this chart, "" inherits it.
*/}}
{{- define "classification-monitor.gatewayEnabled" -}}
{{- $local := .Values.httpRoute.enabled -}}
{{- if kindIs "bool" $local -}}
{{- $local -}}
{{- else -}}
{{- dig "gateway" "enabled" false (.Values.global | default dict) -}}
{{- end -}}
{{- end }}

{{/*
Gateway hostnames as JSON list: httpRoute.hostnames, falling back to global.gateway.hostnames.
*/}}
{{- define "classification-monitor.gatewayHostnames" -}}
{{- .Values.httpRoute.hostnames | default (dig "gateway" "hostnames" (list) (.Values.global | default dict)) | toJson -}}
{{- end }}

{{/*
Gateway parentRefs as JSON list: httpRoute.parentRefs, falling back to global.gateway.parentRefs.
*/}}
{{- define "classification-monitor.gatewayParentRefs" -}}
{{- .Values.httpRoute.parentRefs | default (dig "gateway" "parentRefs" (list) (.Values.global | default dict)) | toJson -}}
{{- end }}

{{/*
Public host name, used e.g. for OAuth redirect URIs: first gateway hostname in Gateway mode,
otherwise the first ingress host.
*/}}
{{- define "classification-monitor.publicHost" -}}
{{- if eq (include "classification-monitor.gatewayEnabled" .) "true" -}}
{{- $hosts := include "classification-monitor.gatewayHostnames" . | fromJsonArray -}}
{{- if not $hosts -}}
{{- fail "Gateway mode needs at least one hostname in httpRoute.hostnames or global.gateway.hostnames" -}}
{{- end -}}
{{- first $hosts -}}
{{- else -}}
{{- (index .Values.ingress.hosts 0).host -}}
{{- end -}}
{{- end }}
