{{- define "lookupservice.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "lookupservice.fullname" -}}
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

{{- define "lookupservice.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "lookupservice.labels" -}}
helm.sh/chart: {{ include "lookupservice.chart" . }}
{{ include "lookupservice.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "lookupservice.selectorLabels" -}}
app.kubernetes.io/name: {{ include "lookupservice.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: lookupservice
{{- end }}

{{/*
LS_DatabaseProvider expects a provider name, while global.database.serverType is numeric
(0=MSSQL, 1=Oracle, 2=Postgres). database.type overrides the mapping if set.
*/}}
{{- define "lookupservice.databaseType" -}}
{{- if .Values.database.type }}
{{- .Values.database.type }}
{{- else }}
{{- $t := .Values.global.database.serverType | toString }}
{{- if eq $t "0" }}SQLServer
{{- else if eq $t "1" }}
{{- fail "Lookup Service documents only SQLServer and PostgreSQL. Set lookupservice.database.type explicitly to use another provider" }}
{{- else if eq $t "2" }}PostgreSQL
{{- else }}
{{- fail (printf "global.database.serverType '%s' is invalid. Use 0 (MSSQL), 1 (Oracle), 2 (Postgres) or set database.type" $t) }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Gateway API mode: "true" renders an HTTPRoute instead of the Ingress.
httpRoute.enabled (true/false) overrides global.gateway.enabled for this chart, "" inherits it.
*/}}
{{- define "lookupservice.gatewayEnabled" -}}
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
{{- define "lookupservice.gatewayHostnames" -}}
{{- .Values.httpRoute.hostnames | default (dig "gateway" "hostnames" (list) (.Values.global | default dict)) | toJson -}}
{{- end }}

{{/*
Gateway parentRefs as JSON list: httpRoute.parentRefs, falling back to global.gateway.parentRefs.
*/}}
{{- define "lookupservice.gatewayParentRefs" -}}
{{- .Values.httpRoute.parentRefs | default (dig "gateway" "parentRefs" (list) (.Values.global | default dict)) | toJson -}}
{{- end }}

{{/*
Public host name, used e.g. for OAuth redirect URIs: first gateway hostname in Gateway mode,
otherwise the first ingress host.
*/}}
{{- define "lookupservice.publicHost" -}}
{{- if eq (include "lookupservice.gatewayEnabled" .) "true" -}}
{{- $hosts := include "lookupservice.gatewayHostnames" . | fromJsonArray -}}
{{- if not $hosts -}}
{{- fail "Gateway mode needs at least one hostname in httpRoute.hostnames or global.gateway.hostnames" -}}
{{- end -}}
{{- first $hosts -}}
{{- else -}}
{{- (index .Values.ingress.hosts 0).host -}}
{{- end -}}
{{- end }}
