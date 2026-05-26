#!/usr/bin/env bash

gcloud auth application-default login
gcloud auth application-default set-quota-project cloudability-it-gemini
gh auth login
hf auth login

git config --global user.email "yzong@redhat.com"
git config --global user.name "Yifan Zong"
