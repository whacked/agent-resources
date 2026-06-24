#!/usr/bin/env bash
# PID 1 for agent-runner.
#
# Runs as root: remaps the in-container `agent` user onto the host user's
# uid/gid (passed as HOST_UID / HOST_GID) so files written to the bind-mounted
# /workspace keep the host owner's identity. Then drops privileges to `agent`
# and execs the requested command (default: a login shell).
set -euo pipefail

HOST_UID="${HOST_UID:-1000}"
HOST_GID="${HOST_GID:-1000}"

cur_uid="$(id -u agent)"
cur_gid="$(id -g agent)"

# -o allows a non-unique id, in case the host id collides with an existing one.
if [ "$HOST_GID" != "$cur_gid" ]; then
  groupmod -o -g "$HOST_GID" agent
fi
if [ "$HOST_UID" != "$cur_uid" ]; then
  usermod -o -u "$HOST_UID" agent
fi

# Keep the agent's home and workspace owned by the (possibly remapped) user.
chown agent:agent /home/agent 2>/dev/null || true
chown agent:agent /workspace 2>/dev/null || true

# Default to a login shell when invoked with no command.
if [ "$#" -eq 0 ]; then
  set -- bash -l
fi

exec gosu agent "$@"
