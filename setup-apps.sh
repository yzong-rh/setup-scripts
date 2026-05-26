#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bashrc_dir="$script_dir/.bashrc.d"

ensure_login_shell_sources_bashrc() {
  local login_shell_rc_path
  local bashrc_source_marker="# setup-apps: source ~/.bashrc"

  if [[ -f "$HOME/.bash_profile" ]]; then
    login_shell_rc_path="$HOME/.bash_profile"
  elif [[ -f "$HOME/.bash_login" ]]; then
    login_shell_rc_path="$HOME/.bash_login"
  elif [[ -f "$HOME/.profile" ]]; then
    login_shell_rc_path="$HOME/.profile"
  else
    login_shell_rc_path="$HOME/.bash_profile"
  fi

  touch "$login_shell_rc_path"

  if ! grep -Fq "$bashrc_source_marker" "$login_shell_rc_path" \
    && ! grep -Eq '^[[:space:]]*(source|\.)[[:space:]].*\.bashrc([[:space:]]|$)' "$login_shell_rc_path"; then
    cat >> "$login_shell_rc_path" <<'EOF'

# setup-apps: source ~/.bashrc
if [ -f ~/.bashrc ]; then
  . ~/.bashrc
fi
EOF
  fi
}

ensure_bashrc_d_loader() {
  local bashrc_path="$HOME/.bashrc"
  local bashrc_source_marker="# setup-apps: source ~/.bashrc.d"

  touch "$bashrc_path"

  if ! grep -Fq "$bashrc_source_marker" "$bashrc_path" \
    && ! grep -Eq '^[[:space:]]*(for|source|\.)[[:space:]].*\.bashrc\.d' "$bashrc_path"; then
    cat >> "$bashrc_path" <<'EOF'

# setup-apps: source ~/.bashrc.d
if [ -d ~/.bashrc.d ]; then
  for bashrc_snippet in ~/.bashrc.d/*; do
    if [ -f "$bashrc_snippet" ]; then
      . "$bashrc_snippet"
    fi
  done
fi

unset bashrc_snippet
EOF
  fi
}

cd "$HOME"

ensure_login_shell_sources_bashrc
mkdir -p "$HOME/.bashrc.d"
ensure_bashrc_d_loader

for bashrc_snippet in "$bashrc_dir"/*; do
  if [[ -f "$bashrc_snippet" ]]; then
    install -m 0644 "$bashrc_snippet" "$HOME/.bashrc.d/$(basename "$bashrc_snippet")"
  fi
done

git config --global user.email "yzong@redhat.com"
git config --global user.name "Yifan Zong"

bash "$script_dir/ripgrep/install.sh"

bash "$script_dir/vllm/install.sh"

bash "$script_dir/neovim/install.sh"

bash "$script_dir/pi/install.sh"
