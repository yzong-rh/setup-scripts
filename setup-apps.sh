#!/usr/bin/env bash

set -euo pipefail

git config pull.rebase true

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bashrc_dir="$script_dir/.bashrc.d"

cd "$HOME"

mkdir -p "$HOME/.bashrc.d"

shopt -s nullglob
for bashrc_snippet in "$bashrc_dir"/*; do
  if [[ -f "$bashrc_snippet" ]]; then
    install -m 0644 "$bashrc_snippet" "$HOME/.bashrc.d/$(basename "$bashrc_snippet")"
  fi
done
shopt -u nullglob

bash "$script_dir/vllm/install.sh"

bash "$script_dir/neovim/install.sh"

bash "$script_dir/pi/install.sh"
