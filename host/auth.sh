#!/usr/bin/env bash

cd "$HOME/vllm"
source .venv/bin/activate
gcloud auth application-default login
gcloud auth application-default set-quota-project cloudability-it-gemini
gh auth login
hf auth login
