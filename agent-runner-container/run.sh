#!/usr/bin/env bash
# Launch the agent-runner container (or run a one-off command in it).
#
# Canonical launcher — `nix run .#run` / `.#up` and the Makefile all call this.
#
#   ./run.sh                 # interactive login shell as `agent` in /workspace
#   ./run.sh claude          # run a single command, then exit
#   WORKSPACE=/path ./run.sh  # bind a different host dir to /workspace
#
# Defaults:
#   - binds $PWD on the host to /workspace in the container
#   - makes host.docker.internal reachable (works on Linux too, harmless on
#     Docker Desktop where it already resolves)
#   - maps the host user's uid/gid onto the container's `agent` user
set -euo pipefail

IMAGE="${AGENT_RUNNER_IMAGE:-agent-runner:latest}"
NAME="${AGENT_RUNNER_NAME:-agent-runner}"
WORKSPACE="${WORKSPACE:-$PWD}"

if ! command -v docker >/dev/null 2>&1; then
  echo "error: 'docker' not found on PATH — Docker Desktop / engine is required" >&2
  exit 127
fi

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "error: image '$IMAGE' not found — build it first (nix run .#build-image)" >&2
  exit 1
fi

exec docker run --rm -it \
  --name "$NAME" \
  --add-host=host.docker.internal:host-gateway \
  --volume "$WORKSPACE:/workspace" \
  --workdir /workspace \
  --env HOST_UID="$(id -u)" \
  --env HOST_GID="$(id -g)" \
  --env HOST_USER="${USER:-agent}" \
  "$IMAGE" "$@"
