{{- define "batchreview.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "batchreview.fullname" -}}
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

{{- define "batchreview.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "batchreview.labels" -}}
helm.sh/chart: {{ include "batchreview.chart" . }}
{{ include "batchreview.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "batchreview.selectorLabels" -}}
app.kubernetes.io/name: {{ include "batchreview.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: batchreview
{{- end }}

{{/*
pathBase without trailing slash, e.g. "/batchreview". Used for the nginx location
blocks and the OAuth redirect URI, so both always match the ingress path.
*/}}
{{- define "batchreview.pathBase" -}}
{{- .Values.env.pathBase | trimSuffix "/" }}
{{- end }}

{{/*
Gateway API mode: "true" renders an HTTPRoute instead of the Ingress.
httpRoute.enabled (true/false) overrides global.gateway.enabled for this chart, "" inherits it.
*/}}
{{- define "batchreview.gatewayEnabled" -}}
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
{{- define "batchreview.gatewayHostnames" -}}
{{- .Values.httpRoute.hostnames | default (dig "gateway" "hostnames" (list) (.Values.global | default dict)) | toJson -}}
{{- end }}

{{/*
Gateway parentRefs as JSON list: httpRoute.parentRefs, falling back to global.gateway.parentRefs.
*/}}
{{- define "batchreview.gatewayParentRefs" -}}
{{- .Values.httpRoute.parentRefs | default (dig "gateway" "parentRefs" (list) (.Values.global | default dict)) | toJson -}}
{{- end }}

{{/*
Public host name, used e.g. for OAuth redirect URIs: first gateway hostname in Gateway mode,
otherwise the first ingress host.
*/}}
{{- define "batchreview.publicHost" -}}
{{- if eq (include "batchreview.gatewayEnabled" .) "true" -}}
{{- $hosts := include "batchreview.gatewayHostnames" . | fromJsonArray -}}
{{- if not $hosts -}}
{{- fail "Gateway mode needs at least one hostname in httpRoute.hostnames or global.gateway.hostnames" -}}
{{- end -}}
{{- first $hosts -}}
{{- else -}}
{{- (index .Values.ingress.hosts 0).host -}}
{{- end -}}
{{- end }}
