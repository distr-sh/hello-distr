{{/*
Expand the name of the chart.
*/}}
{{- define "hello-distr.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified postgresql name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "hello-distr.postgresql.fullname" -}}
{{- include "common.names.dependency.fullname" (dict "chartName" "postgresql" "chartValues" .Values.postgresql "context" $) -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "hello-distr.fullname" -}}
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
{{- define "hello-distr.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "hello-distr.labels" -}}
helm.sh/chart: {{ include "hello-distr.chart" . }}
{{ include "hello-distr.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "hello-distr.selectorLabels" -}}
app.kubernetes.io/name: {{ include "hello-distr.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Component labels — adds app.kubernetes.io/component to common labels.
Usage: {{ include "hello-distr.component.labels" (dict "component" "backend" "context" .) }}
*/}}
{{- define "hello-distr.component.labels" -}}
{{ include "hello-distr.labels" .context }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/*
Component selector labels — adds app.kubernetes.io/component to selector labels.
Usage: {{ include "hello-distr.component.selectorLabels" (dict "component" "backend" "context" .) }}
*/}}
{{- define "hello-distr.component.selectorLabels" -}}
{{ include "hello-distr.selectorLabels" .context }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "hello-distr.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "hello-distr.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the PostgreSQL connection URI
*/}}
{{- define "hello-distr.databaseUri" -}}
{{- printf "postgresql://%s:$(DATABASE_PASSWORD)@%s:%s/%s?sslmode=disable" .Values.postgresql.auth.username (include "hello-distr.databaseHost" .) (include "hello-distr.databasePort" .) .Values.postgresql.auth.database -}}
{{- end -}}

{{/*
Return the PostgreSQL Hostname
*/}}
{{- define "hello-distr.databaseHost" -}}
{{- if .Values.postgresql.enabled }}
  {{- if eq .Values.postgresql.architecture "replication" }}
    {{- printf "%s-%s" (include "hello-distr.postgresql.fullname" .) "primary" | trunc 63 | trimSuffix "-" -}}
  {{- else -}}
    {{- print (include "hello-distr.postgresql.fullname" .) -}}
  {{- end -}}
{{- else -}}
  {{- print .Values.externalDatabase.host -}}
{{- end -}}
{{- end -}}

{{/*
Return the PostgreSQL Port
*/}}
{{- define "hello-distr.databasePort" -}}
{{- if .Values.postgresql.enabled }}
    {{- print .Values.postgresql.service.ports.postgresql -}}
{{- else -}}
    {{- printf "%d" (.Values.externalDatabase.port | int ) -}}
{{- end -}}
{{- end -}}

{{/*
Return the PostgreSQL Secret Name
*/}}
{{- define "hello-distr.databaseSecretName" -}}
{{- if .Values.postgresql.enabled }}
    {{- if .Values.postgresql.auth.existingSecret -}}
    {{- print .Values.postgresql.auth.existingSecret -}}
    {{- else -}}
    {{- print (include "hello-distr.postgresql.fullname" .) -}}
    {{- end -}}
{{- else if .Values.externalDatabase.existingSecret -}}
    {{- print .Values.externalDatabase.existingSecret -}}
{{- else -}}
    {{- printf "%s-%s" (include "hello-distr.fullname" .) "externaldb" -}}
{{- end -}}
{{- end -}}

{{/*
Backend environment variables for database connection.
*/}}
{{- define "hello-distr.backendEnv" -}}
{{- if .Values.postgresql.enabled }}
- name: DATABASE_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "hello-distr.databaseSecretName" . }}
      key: password
{{- end }}
- name: DB_URL
  {{- if .Values.postgresql.enabled }}
  value: {{ include "hello-distr.databaseUri" . }}
  {{- else if .Values.externalDatabase.uri }}
  value: {{ .Values.externalDatabase.uri }}
  {{- else }}
  valueFrom:
    secretKeyRef:
      name: {{ include "hello-distr.databaseSecretName" . }}
      key: {{ .Values.externalDatabase.existingSecretUriKey }}
  {{- end }}
{{- end }}

{{/*
Shared environment variables for all components.
*/}}
{{- define "hello-distr.sharedEnv" -}}
- name: HELLO_DISTR_HOST
  value: {{ .Values.config.host | quote }}
- name: HELLO_DISTR_PROTOCOL
  value: {{ .Values.config.protocol | quote }}
- name: HELLO_DISTR_DB_NAME
  value: {{ .Values.config.dbName | quote }}
{{- end }}
