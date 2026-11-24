#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="${1:-ai-run.jsonl}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${SCRIPT_DIR}/../ai-nginx-deployment.yaml"

json_escape() {
  local value=$1
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '%s' "$value"
}

run_logged() {
  local step=$1
  shift

  local cmd output status output_b64 ts cmd_json
  printf -v cmd '%q ' "$@"
  cmd=${cmd% }

  if output=$("$@" 2>&1); then
    status=0
  else
    status=$?
  fi

  output_b64=$(printf '%s' "$output" | base64 | tr -d '\n')
  ts=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
  cmd_json=$(json_escape "$cmd")

  if ! printf '{"ts":"%s","step":"%s","cmd":"%s","output_b64":"%s"}\n' \
    "$ts" "$step" "$cmd_json" "$output_b64" >> "$LOG_FILE"; then
    return 1
  fi

  return "$status"
}

cleanup() {
  local exit_status=$?
  local cleanup_status=0
  trap - EXIT

  if run_logged cleanup_cluster k3d cluster delete ai; then
    :
  else
    cleanup_status=$?
  fi

  if [[ $exit_status -eq 0 ]]; then
    exit_status=$cleanup_status
  fi
  exit "$exit_status"
}

trap cleanup EXIT
: >> "$LOG_FILE"

run_logged create_cluster k3d cluster create ai
run_logged use_context kubectl config use-context k3d-ai
run_logged apply_manifest kubectl apply -f "$MANIFEST"
run_logged get_deployments kubectl get deployments -o json
run_logged get_service kubectl get svc ai-nginx-service -o json
run_logged get_pods kubectl get pods -l app=nginx -o json
run_logged rollout_status kubectl rollout status deployment/ai-nginx-deployment