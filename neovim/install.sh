#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
nvim_config_src="$script_dir/.config/nvim"
vllm_nvim_src="$script_dir/vllm/.nvim.lua"

bin_dir="$HOME/.local/bin"
bin_path="$bin_dir/nvim"
nvim_install_dir="$HOME/.local/nvim-linux-x86_64"

if [[ ! -x "$nvim_install_dir/bin/nvim" ]]; then
  mkdir -p "$bin_dir" "$HOME/.local"

  tmp_dir="$(mktemp -d)"
  trap 'rm -rf -- "$tmp_dir"' EXIT

  curl -fL --retry 3 \
    "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz" \
    -o "$tmp_dir/nvim-linux-x86_64.tar.gz"

  rm -rf -- "$nvim_install_dir"
  tar --no-same-owner -xzf "$tmp_dir/nvim-linux-x86_64.tar.gz" -C "$HOME/.local"
fi

mkdir -p "$bin_dir"
ln -sfn "$nvim_install_dir/bin/nvim" "$bin_path"

mkdir -p "$HOME/.config"
cp -a "$nvim_config_src" "$HOME/.config/"

if [[ -d "$HOME/vllm" ]]; then
  install -m 0644 "$vllm_nvim_src" "$HOME/vllm/.nvim.lua"
else
  printf 'Warning: %s does not exist; skipping vLLM Neovim config.\n' "$HOME/vllm" >&2
fi

uv tool install --upgrade basedpyright --no-cache
uv tool update-shell
