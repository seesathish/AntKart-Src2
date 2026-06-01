{{/*
=============================================================================
  antkart-service — TEMPLATE HELPERS
  File: charts/antkart-service/templates/_helpers.tpl

  Standard Helm helpers. The Helm convention is to put naming and labelling
  helpers in this file so the actual resource templates stay short.
=============================================================================
*/}}

{{/*
  Generate the canonical name for a release of this chart.

  Order of precedence:
    1. .Values.fullnameOverride  — explicit override
    2. .Release.Name             — what the user passed to `helm install <name>`
    3. fallback to .Chart.Name   — almost never used

  The result is truncated to 63 chars (Kubernetes label-value limit).
*/}}
{{- define "antkart-service.fullname" -}}
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
  Chart-level name (used for labels). Always the chart name regardless of
  release name — useful for filtering "all resources from this chart" across
  the cluster: kubectl get all -l app.kubernetes.io/name=antkart-service
*/}}
{{- define "antkart-service.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
  Common labels applied to every resource. Standard Kubernetes recommended
  labels (https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/).

  app.kubernetes.io/name      — chart name (constant across releases)
  app.kubernetes.io/instance  — release name (one per `helm install`)
  app.kubernetes.io/version   — appVersion from Chart.yaml
  app.kubernetes.io/managed-by — Helm always
  app.kubernetes.io/component  — added by some templates (e.g., "web", "worker")
*/}}
{{- define "antkart-service.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "antkart-service.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
  Selector labels — the SUBSET of common labels that Deployments and Services
  use to match pods. These MUST be stable across upgrades, so chart version
  and app version are excluded here (they change on upgrade and would orphan
  existing pods).
*/}}
{{- define "antkart-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "antkart-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
  Service account name. Either explicit override or "<release>-sa".
*/}}
{{- define "antkart-service.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (printf "%s-sa" (include "antkart-service.fullname" .)) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}
