{{- define "extraction-designer.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "extraction-designer.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "extraction-designer.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "extraction-designer.labels" -}}
helm.sh/chart: {{ include "extraction-designer.chart" . }}
{{ include "extraction-designer.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "extraction-designer.selectorLabels" -}}
app.kubernetes.io/name: {{ include "extraction-designer.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: extraction
{{- end }}

{{/*
Gateway API mode: "true" renders an HTTPRoute instead of the Ingress.
httpRoute.enabled (true/false) overrides global.gateway.enabled for this chart, "" inherits it.
*/}}
{{- define "extraction-designer.gatewayEnabled" -}}
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
{{- define "extraction-designer.gatewayHostnames" -}}
{{- .Values.httpRoute.hostnames | default (dig "gateway" "hostnames" (list) (.Values.global | default dict)) | toJson -}}
{{- end }}

{{/*
Gateway parentRefs as JSON list: httpRoute.parentRefs, falling back to global.gateway.parentRefs.
*/}}
{{- define "extraction-designer.gatewayParentRefs" -}}
{{- .Values.httpRoute.parentRefs | default (dig "gateway" "parentRefs" (list) (.Values.global | default dict)) | toJson -}}
{{- end }}

{{/*
Public host name, used e.g. for OAuth redirect URIs: first gateway hostname in Gateway mode,
otherwise the first ingress host.
*/}}
{{- define "extraction-designer.publicHost" -}}
{{- if eq (include "extraction-designer.gatewayEnabled" .) "true" -}}
{{- $hosts := include "extraction-designer.gatewayHostnames" . | fromJsonArray -}}
{{- if not $hosts -}}
{{- fail "Gateway mode needs at least one hostname in httpRoute.hostnames or global.gateway.hostnames" -}}
{{- end -}}
{{- first $hosts -}}
{{- else -}}
{{- (index .Values.ingress.hosts 0).host -}}
{{- end -}}
{{- end }}
