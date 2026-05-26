# Podman Tutorial: vLLM development container

The walkthrough below keeps the container image focused on system dependencies for developing `vLLM` and fetches application bootstrap from the private repo `git@github.com:yzong-rh/setup-scripts.git` at container startup. The launcher uses `gh repo clone` with a read-only GitHub token, mounts Google Application Default Credentials for later Vertex AI use, and then runs `setup-apps.sh`.

It assumes:

- the base image is `pytorch/pytorch:2.11.0-cuda13.0-cudnn9-devel`
- each container receives a read-only GitHub token, a read-only Hugging Face token, and a Google ADC credential file
- the read-only GitHub token can read the private `yzong-rh/setup-scripts` repo
- the only shared writable state is the Hugging Face Hub cache
- the launcher hands off application bootstrap to `setup-apps.sh` from the private setup repo
- the coding agent's Vertex AI-specific setup can happen later in `setup-apps.sh`
- the launcher can optionally pass a host service URL into the container at runtime

Each agent gets its own:

- container
- persistent `/home/dev`
- application state under `/home/dev`, laid out by `setup-apps.sh`

All agents share only:

- `/shared-cache`

That keeps agent work isolated while reusing model downloads.

## Prerequisites

- Podman is installed
- the container can reach the internet
- you have a read-only GitHub token on the host
- you have a read-only Hugging Face token on the host
- you have a Google credential JSON on the host that can be used as Application Default Credentials for Vertex AI

`vLLM` is public, but this tutorial still passes a read-only GitHub token because the launcher uses it with `gh` to clone the private `setup-scripts` repo and the agent can still use authenticated GitHub access without getting write permissions.

If an agent needs GPU access for builds or tests, add the right Podman device flags to `podman run`, for example:

```bash
--device nvidia.com/gpu=all
```

## 1. Define the Bootstrap Source

The bootstrap entrypoint lives in the private repo `git@github.com:yzong-rh/setup-scripts.git`.

Inside the container, the launcher uses `gh repo clone yzong-rh/setup-scripts` with `GH_TOKEN`. That keeps SSH keys out of the container while still keeping the setup logic outside the base image.

## 2. Build the System Image

Create a `Containerfile`:

```dockerfile
FROM docker.io/pytorch/pytorch:2.11.0-cuda13.0-cudnn9-devel

ENV HOME=/home/dev

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    bash \
    build-essential \
    ca-certificates \
    curl \
    git \
    jq \
    less \
    procps \
    rsync \
    tmux \
    gh \
    nodejs \
    npm \
    && python -m pip install --no-cache-dir uv \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p "${HOME}" /shared-cache

ENV HF_HUB_CACHE=/shared-cache
WORKDIR ${HOME}

CMD ["/bin/bash"]
```

Build it:

```bash
podman build -t localhost/vllm-system:latest .
```

The image does not create a host-specific user. Instead, the launcher runs the container as the caller's numeric UID/GID with `--userns=keep-id` and `--user "$(id -u):$(id -g)"`, while injecting a `dev` passwd/group entry at runtime. That avoids per-host rebuilds while still letting bind mounts and secrets line up with the caller's host permissions.

This base image does not need `google-cloud-aiplatform`, `google-genai`, or `gcloud` just to let the coding agent use Vertex AI later. The launcher will mount ADC at runtime, and `setup-apps.sh` can install and configure the coding agent afterwards.

## 3. Create the Required Secrets

This tutorial uses the fixed secret names `gh-read-token`, `hf-read-token`, and `gcp-vertex-adc`.

Create them on the host:

```bash
printf '%s' "$GH_READONLY_TOKEN" | podman secret create gh-read-token -
printf '%s' "$HF_READ_TOKEN" | podman secret create hf-read-token -
podman secret create gcp-vertex-adc /path/to/adc.json
```

Use an ADC JSON that Google tooling can discover through `GOOGLE_APPLICATION_CREDENTIALS`, such as a service account key JSON or a Workload Identity Federation credential configuration JSON.

Credential scope:

- GitHub: `Contents` read-only for the private `yzong-rh/setup-scripts` repo, plus `Issues` and `Pull requests` read-only if the agent needs them
- Hugging Face: read-only access to the gated or private repos the agent needs
- GCP: the identity in the ADC file needs Vertex AI access, typically `roles/aiplatform.user`, and the target project must have `aiplatform.googleapis.com` enabled

## 4. Create the Launcher

Set the shared cache location on the host:

```bash
export CACHE_DIR=/data-tier-1/engine
```

Create `run-agent.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

AGENT_NAME="${1:?usage: $0 <agent-name> [host-service-port]}"
HOST_SERVICE_PORT="${2:-}"

IMAGE="localhost/vllm-system:latest"
REPO_URL="https://github.com/vllm-project/vllm.git"
CACHE_DIR="${CACHE_DIR:?set CACHE_DIR to the host shared cache directory}"
GH_SECRET_NAME="gh-read-token"
HF_SECRET_NAME="hf-read-token"
GCP_SECRET_NAME="gcp-vertex-adc"

HOME_VOLUME="agent-${AGENT_NAME}-home"
CONTAINER_NAME="agent-${AGENT_NAME}"

HOST_SERVICE_ARGS=()
if [ -n "$HOST_SERVICE_PORT" ]; then
  HOST_SERVICE_ARGS+=(-e "HOST_SERVICE_URL=http://host.containers.internal:${HOST_SERVICE_PORT}")
fi

mkdir -p "$CACHE_DIR"
if ! podman volume exists "$HOME_VOLUME" &>/dev/null; then
  podman volume create "$HOME_VOLUME" >/dev/null
fi

podman run --rm -it \
  --userns keep-id \
  --user "$(id -u):$(id -g)" \
  --group-entry "dev:x:$(id -g):" \
  --passwd-entry "dev:x:$(id -u):$(id -g):dev:/home/dev:/bin/bash" \
  --group-add keep-groups \
  --name "$CONTAINER_NAME" \
  --hostname "$CONTAINER_NAME" \
  "${HOST_SERVICE_ARGS[@]}" \
  --secret "source=${GH_SECRET_NAME},type=mount,target=gh_token,uid=$(id -u),gid=$(id -g),mode=0400" \
  --secret "source=${HF_SECRET_NAME},type=mount,target=hf_token,uid=$(id -u),gid=$(id -g),mode=0400" \
  --secret "source=${GCP_SECRET_NAME},type=mount,target=gcp_adc.json,uid=$(id -u),gid=$(id -g),mode=0400" \
  -e AGENT_NAME="$AGENT_NAME" \
  -e HOME=/home/dev \
  -e REPO_URL="$REPO_URL" \
  -e HF_HUB_CACHE=/shared-cache \
  -e HF_TOKEN_PATH=/run/secrets/hf_token \
  -e GOOGLE_APPLICATION_CREDENTIALS=/run/secrets/gcp_adc.json \
  -v "$HOME_VOLUME":/home/dev:U \
  -v "${CACHE_DIR}:/shared-cache" \
  "$IMAGE" \
  bash -lc '
    set -euo pipefail

    export GH_TOKEN="$(< /run/secrets/gh_token)"

    setup_dir="$(mktemp -d)"
    trap "rm -rf \"$setup_dir\"" EXIT

    gh repo clone yzong-rh/setup-scripts "$setup_dir" -- --depth 1

    chmod +x "$setup_dir/setup-apps.sh"
    exec "$setup_dir/setup-apps.sh"
  '
```

Make it executable:

```bash
chmod +x run-agent.sh
```

What this does:

- creates one persistent home volume per agent
- creates the home volume only if it does not already exist
- bind-mounts the shared host cache directory from `CACHE_DIR` at `/shared-cache`
- runs the container as the invoking host UID/GID and injects a matching `dev` passwd/group entry at runtime, so mounts stay accessible without rebuilding per host
- preserves host supplementary groups so group-writable cache directories stay writable in the container
- mounts the `gh-read-token`, `hf-read-token`, and `gcp-vertex-adc` secrets into every container
- exposes the mounted Google ADC file through `GOOGLE_APPLICATION_CREDENTIALS` so later setup can use Vertex AI without `gcloud auth login`
- clones the private `setup-scripts` repo with `gh` into a temporary directory on each launch
- passes agent and repo context into the container for `setup-apps.sh`
- accepts an optional host-service port as the third argument
- leaves the internal layout of `/home/dev` to `setup-apps.sh`
- runs `setup-apps.sh` from the private setup repo instead of baking it into the image

## 5. Start Agents

Run one agent per terminal:

```bash
./run-agent.sh 1
./run-agent.sh 2
./run-agent.sh reviewer-a
```

If an agent needs to reach a host service on a non-default port, pass that port as the third argument:

```bash
./run-agent.sh 1 8081
```

The launcher already passes the read-only GitHub and Hugging Face tokens, and it mounts the Google ADC file at `GOOGLE_APPLICATION_CREDENTIALS`. The GitHub token is also used by `gh` to clone the private `setup-scripts` repo.

If the coding agent will use Vertex AI, keep the auth handoff in the launcher and defer the coding agent-specific setup to `setup-apps.sh`, for example `CLAUDE_CODE_USE_VERTEX=1`, `GOOGLE_CLOUD_PROJECT=...`, and `CLOUD_ML_REGION=global`.

Because each agent has its own persistent `/home/dev`, `setup-apps.sh` can keep each agent's state, checkouts, and local environments separate without the image defining that layout in advance.

Because the setup repo is cloned on each start, changes to `setup-apps.sh` are picked up on the next run without rebuilding the image.

If you want a shell instead of running the bootstrap entrypoint while iterating, replace:

```bash
exec "$setup_dir/setup-apps.sh"
```

with:

```bash
exec bash
```

## 6. Quick Checks

Verify that the system image contains the expected tooling:

```bash
podman run --rm localhost/vllm-system:latest bash -lc '
  gh --version
  git --version
  uv --version
'
```

Your first `./run-agent.sh` invocation also verifies that the read-only GitHub token can authenticate `gh`, clone the private `setup-scripts` repo, find `setup-apps.sh`, and make the mounted ADC file available at `GOOGLE_APPLICATION_CREDENTIALS`.

Extend your checks there to confirm the repo layout it chose under `/home/dev`, the `uv` environment, agent startup, and, if the coding agent will use Vertex AI, that `test -r "$GOOGLE_APPLICATION_CREDENTIALS"` succeeds before `setup-apps.sh` configures the coding agent.

If you passed a host-service port when launching the container, verify it from inside a shell with:

```bash
curl "$HOST_SERVICE_URL/health"
```

Important:

- from inside the container, `localhost` means the container itself
- use `host.containers.internal` for host services
- pass the host-service port at launch time instead of baking a URL into the image
- share `HF_HUB_CACHE`, not `HF_HOME`

## Cleanup

List volumes:

```bash
podman volume ls
```

Remove one agent's local state:

```bash
podman volume rm agent-1-home
```

The shared cache lives on the host at `CACHE_DIR`, so inspect or clean it directly there when no agent still needs it.

If you need to rotate or remove the secrets:

```bash
podman secret rm gh-read-token hf-read-token gcp-vertex-adc
```

Only remove shared state or secrets when no agent still needs them.
