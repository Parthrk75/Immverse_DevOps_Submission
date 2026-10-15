{{- define "app.image" -}}
{{- if not .Values.image.digest }}{{ fail "image.digest is required (deploy by digest, never by tag)" }}{{ end -}}
{{ .Values.image.repository }}@{{ .Values.image.digest }}
{{- end -}}
{{- define "app.labels" -}}
app.kubernetes.io/name: app
app.kubernetes.io/managed-by: argocd
tenant: {{ .Values.tenant | quote }}
{{- end -}}
{{- define "app.env" -}}
- name: DATABASE_HOST
{{- if .Values.pgbouncer.enabled }}
  value: pgbouncer
{{- else }}
  valueFrom: {secretKeyRef: {name: app-secrets, key: pg_host_direct}}
{{- end }}
- name: DATABASE_PORT
  value: {{ if .Values.pgbouncer.enabled }}"6432"{{ else }}"5432"{{ end }}
- name: DATABASE_USER
  valueFrom: {secretKeyRef: {name: app-secrets, key: pg_user}}
- name: DATABASE_PASSWORD
  valueFrom: {secretKeyRef: {name: app-secrets, key: pg_password}}
- name: DATABASE_NAME
  value: app
- name: REDIS_HOST
  valueFrom: {secretKeyRef: {name: app-secrets, key: redis_host}}
- name: REDIS_PASSWORD
  valueFrom: {secretKeyRef: {name: app-secrets, key: redis_password}}
- name: RUN_MIGRATIONS
  value: "false"
{{- end -}}
