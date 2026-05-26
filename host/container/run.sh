#!/usr/bin/env bash
set -euo pipefail

readonly IMAGE="localhost/vllm-system:latest"
readonly GH_SECRET_NAME="gh-read-token"
readonly HF_SECRET_NAME="hf-read-token"
readonly GCP_SECRET_NAME="gcp-vertex-adc"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options] <pod-name>

Start an interactive vLLM development container for <pod-name>.
Each pod gets its own container and home volume; the Hugging Face cache
is shared across pods.

Options:
  -g, --gpu              Pass NVIDIA GPUs into the container
  -p, --host-port PORT   Set HOST_SERVICE_URL (http://host.containers.internal:PORT).
                         The host service must listen on 0.0.0.0, not 127.0.0.1.
  -h, --help             Show this help and exit

Environment:
  CACHE_DIR            Host directory bind-mounted at /shared-cache
  CUDA_VISIBLE_DEVICES   Selects which GPUs to use when -g is passed

Examples:
  $(basename "$0") reviewer-a
  CUDA_VISIBLE_DEVICES=0 $(basename "$0") -g worker-1
  $(basename "$0") -g -p 8081 pod-2

Prerequisites:
  Image:   ${IMAGE}  (./build.sh)
  Secrets: ${GH_SECRET_NAME}, ${HF_SECRET_NAME}, ${GCP_SECRET_NAME}
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

POD_NAME=""
HOST_SERVICE_PORT=""
USE_GPU=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    -g | --gpu)
      USE_GPU=true
      shift
      ;;
    -p | --host-port)
      [[ $# -ge 2 && -n "${2:-}" ]] || die "--host-port requires a port number"
      HOST_SERVICE_PORT="$2"
      shift 2
      ;;
    -*)
      die "unknown option: $1 (try --help)"
      ;;
    *)
      [[ -z "$POD_NAME" ]] || die "unexpected argument: $1"
      POD_NAME="$1"
      shift
      ;;
  esac
done

[[ -n "$POD_NAME" ]] || { usage >&2; exit 1; }

readonly CACHE_DIR="${CACHE_DIR:-}"
[[ -n "$CACHE_DIR" ]] || die "CACHE_DIR must be set to the host shared cache directory"

CONTAINER_NAME="pod-${POD_NAME}"
HOME_VOLUME="pod-${POD_NAME}-home"
readonly CONTAINER_HOME="/home/dev"
readonly CONTAINER_UID="$(id -u)"
readonly CONTAINER_GID="$(id -g)"

podman_args=(
  --rm -it
  --userns keep-id
  --user "${CONTAINER_UID}:${CONTAINER_GID}"
  --group-entry "dev:x:${CONTAINER_GID}:"
  --passwd-entry "dev:x:${CONTAINER_UID}:${CONTAINER_GID}:dev:${CONTAINER_HOME}:/bin/bash"
  --group-add keep-groups
  --name "$CONTAINER_NAME"
  --hostname "$CONTAINER_NAME"
  --secret "source=${GH_SECRET_NAME},type=mount,target=gh_token,uid=${CONTAINER_UID},gid=${CONTAINER_GID},mode=0400"
  --secret "source=${HF_SECRET_NAME},type=mount,target=hf_token,uid=${CONTAINER_UID},gid=${CONTAINER_GID},mode=0400"
  --secret "source=${GCP_SECRET_NAME},type=mount,target=gcp_adc.json,uid=${CONTAINER_UID},gid=${CONTAINER_GID},mode=0400"
  -e POD_NAME="$POD_NAME"
  -e HOME="${CONTAINER_HOME}"
  -e HF_HUB_CACHE=/shared-cache
  -e HF_TOKEN_PATH=/run/secrets/hf_token
  -e GOOGLE_APPLICATION_CREDENTIALS=/run/secrets/gcp_adc.json
  -v "$HOME_VOLUME":"${CONTAINER_HOME}":U
  -v "${CACHE_DIR}:/shared-cache:z"
)

if [[ "$USE_GPU" == true ]]; then
  podman_args+=(--device nvidia.com/gpu=all)
  [[ -n "${CUDA_VISIBLE_DEVICES:-}" ]] && \
    podman_args+=(-e "CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES}")
fi
[[ -n "$HOST_SERVICE_PORT" ]] && \
  podman_args+=(-e "HOST_SERVICE_URL=http://host.containers.internal:${HOST_SERVICE_PORT}")

mkdir -p "$CACHE_DIR"
if ! podman volume exists "$HOME_VOLUME" &>/dev/null; then
  podman volume create "$HOME_VOLUME" >/dev/null
fi

podman run "${podman_args[@]}" "$IMAGE" bash -lc '
  set -euo pipefail

  export GH_TOKEN="$(< /run/secrets/gh_token)"

  exec bash -l
'
