#!/usr/bin/env bash

set -euo pipefail

repo_dir="$HOME/vllm"

if [[ -e "$repo_dir" ]]; then
  printf 'Warning: %s already exists; skipping vLLM install.\n' "$repo_dir" >&2
  exit 0
fi

gh repo clone vllm-project/vllm "$repo_dir"

cd "$repo_dir"
uv venv --python 3.12 --seed --managed-python
source .venv/bin/activate

# Reset the repo to earlier commit to avoid the issue with precompiled wheels.
git reset HEAD~10 --hard
VLLM_USE_PRECOMPILED=1 uv pip install --no-cache --editable . --torch-backend=auto

uv pip install --no-cache -r requirements/lint.txt --torch-backend=auto
uv pip install --no-cache -r requirements/test/cuda.in --torch-backend=auto
pre-commit install
