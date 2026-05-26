#!/usr/bin/env bash
set -euo pipefail

podman build \
  -t localhost/vllm-system:latest \
  .

secret_exists() {
  podman secret exists "$1" &>/dev/null
}

confirm_secret_update() {
  local name="$1"
  local answer
  read -r -p "Secret '${name}' already exists. Update it? [y/N]: " answer
  case "${answer,,}" in
    y | yes) return 0 ;;
    *) return 1 ;;
  esac
}

create_secret_from_stdin() {
  local name="$1"
  local prompt="$2"
  local value

  if secret_exists "$name"; then
    if ! confirm_secret_update "$name"; then
      echo "Keeping existing secret '${name}'."
      return 0
    fi
    podman secret rm "$name"
  fi

  read -r -s -p "$prompt" value
  echo
  printf '%s' "$value" | podman secret create "$name" -
}

create_secret_from_file() {
  local name="$1"
  local prompt="$2"
  local default_path="$3"
  local path

  if secret_exists "$name"; then
    if ! confirm_secret_update "$name"; then
      echo "Keeping existing secret '${name}'."
      return 0
    fi
    podman secret rm "$name"
  fi

  read -r -p "${prompt} [${default_path}]: " path
  path="${path:-$default_path}"
  if [[ ! -f "$path" ]]; then
    echo "File not found: ${path}" >&2
    exit 1
  fi
  podman secret create "$name" "$path"
}

create_secret_from_stdin gh-read-token "GH_READONLY_TOKEN: "
create_secret_from_stdin hf-read-token "HF_READ_TOKEN: "
create_secret_from_file gcp-vertex-adc "ADC JSON path" \
  "${HOME}/.config/gcloud/application_default_credentials.json"
