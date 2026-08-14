#!/usr/bin/env bash

set -euo pipefail

bin_dir="$HOME/.local/bin"
bin_path="$bin_dir/rg"

[[ -x "$bin_path" ]] && exit 0

mkdir -p "$bin_dir"

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT

version="$(
  curl -fsSLI -A "setup-scripts" -o /dev/null -w '%{url_effective}' \
    https://github.com/BurntSushi/ripgrep/releases/latest
)"
version="${version%/}"
version="${version##*/}"

archive="ripgrep-${version}-x86_64-unknown-linux-musl.tar.gz"
extract_dir="ripgrep-${version}-x86_64-unknown-linux-musl"

curl -fL --retry 3 -A "setup-scripts" \
  "https://github.com/BurntSushi/ripgrep/releases/download/${version}/${archive}" \
  -o "$tmp_dir/${archive}"

tar --no-same-owner -xzf "$tmp_dir/${archive}" -C "$tmp_dir"

install -m 0755 "$tmp_dir/${extract_dir}/rg" "$bin_path"
