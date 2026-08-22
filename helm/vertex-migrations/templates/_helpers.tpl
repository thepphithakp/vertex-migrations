{{- define "vertex-migrations.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "vertex-migrations.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "vertex-migrations.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: migration
{{- end }}

{{- define "vertex-migrations.jdbcUrl" -}}
jdbc:postgresql://{{ .Values.db.host }}:{{ .Values.db.port }}/{{ .Values.db.name }}?sslmode={{ .Values.db.sslMode }}
{{- end }}
