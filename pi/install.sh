#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bashrc_snippet="$script_dir/bashrc.d/pi-anthropic-vertex.sh"

cd "$HOME"

if ! [[ -x "$HOME/.local/bin/pi" ]]; then
  npm install -g --prefix "$HOME/.local" @mariozechner/pi-coding-agent
fi

if [[ ! -f "$bashrc_snippet" ]]; then
  echo "pi-install: missing bashrc snippet: $bashrc_snippet" >&2
  exit 1
fi

mkdir -p "$HOME/.bashrc.d"
install -m 0644 "$bashrc_snippet" "$HOME/.bashrc.d/pi-anthropic-vertex.sh"

mkdir -p "$HOME/.pi/agent"
install -m 0644 "$script_dir/.pi/agent/APPEND_SYSTEM.md" "$HOME/.pi/agent/APPEND_SYSTEM.md"

"$HOME/.local/bin/pi" install git:github.com/twoGiants/pi-anthropic-vertex
"$HOME/.local/bin/pi" install git:github.com/yzong-rh/pi-exa-web-access
"$HOME/.local/bin/pi" install git:github.com/yzong-rh/pi-local-vllm
