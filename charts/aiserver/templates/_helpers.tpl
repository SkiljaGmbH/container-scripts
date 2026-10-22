{{/*
Expand the name of the chart.
*/}}
{{- define "aiserver.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "aiserver.fullname" -}}
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

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "aiserver.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "aiserver.labels" -}}
helm.sh/chart: {{ include "aiserver.chart" . }}
{{ include "aiserver.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "aiserver.selectorLabels" -}}
app.kubernetes.io/name: {{ include "aiserver.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: aiserver
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "aiserver.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "aiserver.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the appropriate apiVersion for ingress.
*/}}
{{- define "aiserver.ingress.apiVersion" -}}
{{- if semverCompare ">=1.19-0" .Capabilities.KubeVersion.GitVersion }}
{{- print "networking.k8s.io/v1" }}
{{- else if semverCompare ">=1.14-0" .Capabilities.KubeVersion.GitVersion }}
{{- print "networking.k8s.io/v1beta1" }}
{{- else }}
{{- print "extensions/v1beta1" }}
{{- end }}
{{- end }}

{{/*
Return the storage configuration based on persistence type
*/}}
{{- define "aiserver.storageConfig" -}}
{{- if eq .Values.persistence.type "ebs" }}
{{- .Values.persistence.ebs | toYaml }}
{{- else if eq .Values.persistence.type "efs" }}
{{- .Values.persistence.efs | toYaml }}
{{- end }}
{{- end }}

{{/*
LLM max process count. Empty falls back to "1" (upstream sample value), independent of GPU mode.
"0" disables this processing type in the container, it does NOT mean "CPU-only".
*/}}
{{- define "aiserver.llm.maxProcessCount" -}}
{{- .Values.config.llm.maxProcessCount | toString | default "1" }}
{{- end }}

{{/*
LLAMA max process count. Empty falls back to "1" (upstream sample value), independent of GPU mode.
"0" disables this processing type in the container, it does NOT mean "CPU-only".
*/}}
{{- define "aiserver.llama.maxProcessCount" -}}
{{- .Values.config.llama.maxProcessCount | toString | default "1" }}
{{- end }}

{{/*
Check if pod affinity should be enabled
Enabled when: persistence.type=ebs AND replicaCount > 1
*/}}
{{- define "aiserver.affinity.enabled" -}}
{{- if or .Values.affinity.enabled (and (eq .Values.persistence.type "ebs") (gt (int .Values.replicaCount) 1)) }}
{{- print "true" }}
{{- else }}
{{- print "false" }}
{{- end }}
{{- end }}

{{/*
Return the proper image name
*/}}
{{- define "aiserver.image" -}}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | default .Chart.AppVersion) }}
{{- end }}

{{/*
Return the proper Docker Image Registry Secret Names
*/}}
{{- define "aiserver.imagePullSecrets" -}}
{{- if .Values.image.pullSecrets }}
imagePullSecrets:
{{- range .Values.image.pullSecrets }}
  - name: {{ . }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Gateway API mode: "true" renders an HTTPRoute instead of the Ingress.
httpRoute.enabled (true/false) overrides global.gateway.enabled for this chart, "" inherits it.
*/}}
{{- define "aiserver.gatewayEnabled" -}}
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
{{- define "aiserver.gatewayHostnames" -}}
{{- .Values.httpRoute.hostnames | default (dig "gateway" "hostnames" (list) (.Values.global | default dict)) | toJson -}}
{{- end }}

{{/*
Gateway parentRefs as JSON list: httpRoute.parentRefs, falling back to global.gateway.parentRefs.
*/}}
{{- define "aiserver.gatewayParentRefs" -}}
{{- .Values.httpRoute.parentRefs | default (dig "gateway" "parentRefs" (list) (.Values.global | default dict)) | toJson -}}
{{- end }}

{{/*
Public host name, used e.g. for OAuth redirect URIs: first gateway hostname in Gateway mode,
otherwise the first ingress host.
*/}}
{{- define "aiserver.publicHost" -}}
{{- if eq (include "aiserver.gatewayEnabled" .) "true" -}}
{{- $hosts := include "aiserver.gatewayHostnames" . | fromJsonArray -}}
{{- if not $hosts -}}
{{- fail "Gateway mode needs at least one hostname in httpRoute.hostnames or global.gateway.hostnames" -}}
{{- end -}}
{{- first $hosts -}}
{{- else -}}
{{- (index .Values.ingress.hosts 0).host -}}
{{- end -}}
{{- end }}
