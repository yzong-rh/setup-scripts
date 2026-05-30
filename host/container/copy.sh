#!/usr/bin/env bash
set -euo pipefail

readonly POD_HOME="/home/dev"

die() { echo "error: $*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") pull <pod> <path-in-pod> [host-dest]
       $(basename "$0") push <pod> <host-path> [path-in-pod]

Copy files to/from a pod's persistent home (${POD_HOME}).
Uses podman cp when the container is running; otherwise copies via its home volume.

Examples:
  $(basename "$0") pull 0 vllm/patch.diff ./patch.diff
  $(basename "$0") push 0 ./patch.diff vllm/patch.diff
EOF
}

pod_path() {
  local p="$1"
  [[ "$p" == /* ]] || p="${POD_HOME}/${p}"
  p="$(realpath -sm -- "$p")"
  [[ "$p" == /shared-cache/* ]] && die 'use \$CACHE_DIR for /shared-cache'
  [[ "$p" == "$POD_HOME" || "$p" == "${POD_HOME}/"* ]] || die "path must be under ${POD_HOME}: ${p}"
  printf '%s\n' "$p"
}

volume_file() {
  local pod="$1" path="$2"
  local vol="pod-${pod}-home"
  podman volume exists "$vol" &>/dev/null || die "no volume ${vol} (start the pod once with run.sh)"
  local root=""
  if [[ "$path" == "${POD_HOME}/"* ]]; then
    root="${path#"${POD_HOME}/"}"
  elif [[ "$path" != "$POD_HOME" ]]; then
    die "path must be under ${POD_HOME}: ${path}"
  fi
  printf '%s\n' "$(podman volume inspect "$vol" --format '{{.Mountpoint}}')/${root}"
}

pod_running() {
  [[ "$(podman container inspect "pod-$1" --format '{{.State.Running}}' 2>/dev/null || echo false)" == true ]]
}

copy() {
  local mode="$1" pod="$2" container_path="$3" host_path="$4"
  local ctr="pod-${pod}"

  if pod_running "$pod"; then
    if [[ "$mode" == pull ]]; then
      podman cp "${ctr}:${container_path}" "$host_path"
    else
      podman cp "$host_path" "${ctr}:${container_path}"
    fi
  elif [[ "$mode" == pull ]]; then
    local src
    src="$(volume_file "$pod" "$container_path")"
    [[ -e "$src" ]] || die "not found: ${src}"
    mkdir -p "$(dirname -- "$host_path")"
    cp -a -- "$src" "$host_path"
  else
    local dest
    dest="$(volume_file "$pod" "$container_path")"
    mkdir -p "$(dirname -- "$dest")"
    cp -a -- "$host_path" "$dest"
  fi

  if [[ "$mode" == pull ]]; then
    echo "copied ${container_path} -> ${host_path}"
  else
    echo "copied ${host_path} -> ${container_path}"
  fi
}

case "${1:-}" in
  -h | --help)
    usage
    ;;
  pull)
    [[ $# -ge 3 ]] || die "pull requires <pod> <path-in-pod> [host-dest]"
    path="$(pod_path "$3")"
    copy pull "$2" "$path" "${4:-./$(basename "$path")}"
    ;;
  push)
    [[ $# -ge 3 ]] || die "push requires <pod> <host-path> [path-in-pod]"
    [[ -e "$3" ]] || die "host path does not exist: $3"
    path="$(pod_path "${4:-${POD_HOME}/$(basename "$3")}")"
    copy push "$2" "$path" "$3"
    ;;
  "" | *)
    usage >&2
    die "${1:+unknown command: $1}"
    ;;
esac
