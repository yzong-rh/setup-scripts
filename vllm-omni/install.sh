#!/usr/bin/env bash

set -euo pipefail

repo_dir="$HOME/vllm-omni"

if [[ -e "$repo_dir" ]]; then
  printf 'Warning: %s already exists; skipping vLLM Omni install.\n' "$repo_dir" >&2
  exit 0
fi

git clone "https://github.com/vllm-project/vllm-omni.git" "$repo_dir"

cd "$repo_dir"
uv venv --python 3.12 --seed --managed-python
source .venv/bin/activate

# Main tracks the vLLM tag in docker/Dockerfile.ci, not the install docs.
vllm_tag="$(awk -F= '/^ARG VLLM_BASE_TAG=/ { print $2; exit }' docker/Dockerfile.ci)"
if [[ -z "$vllm_tag" ]]; then
  printf 'error: could not read VLLM_BASE_TAG from docker/Dockerfile.ci\n' >&2
  exit 1
fi

uv pip install --no-cache "vllm==${vllm_tag#v}" --torch-backend=auto
uv pip install --no-cache --editable . --torch-backend=auto

uv pip install --no-cache pre-commit
pre-commit install
