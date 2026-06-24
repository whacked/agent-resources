# syntax=docker/dockerfile:1
#
# agent-runner — built FROM nixos/nix so the agents are installed by Nix (from
# the pinned llm-agents.nix flake) inside Docker's native-platform build VM.
# No host Linux builder is required: Nix runs in the container.
#
# The base image is pinned by digest for reproducibility. To refresh:
#   docker pull nixos/nix:latest
#   docker inspect --format='{{index .RepoDigests 0}}' nixos/nix:latest
ARG NIX_IMAGE=nixos/nix@sha256:bf1d938835ab96312f098fa6c2e9cab367728e0aad0646ee3e02a787c80d8fb8
FROM ${NIX_IMAGE}

# Enable flakes and point at the llm-agents binary cache so the build pulls
# prebuilt agents instead of compiling them. (root in the build is a trusted
# user, so these substituter/key settings are honoured.)
RUN set -eux; \
    { \
      echo "experimental-features = nix-command flakes"; \
      echo "accept-flake-config = true"; \
      echo "extra-substituters = https://cache.numtide.com"; \
      echo "extra-trusted-public-keys = niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="; \
    } >> /etc/nix/nix.conf

WORKDIR /build

# Only the flake definition is needed to realise the agent + tool environments.
# Copying just these two files keeps this (expensive) layer cached across edits
# to scripts, README, etc.
COPY flake.nix flake.lock ./

# Install the agent layer and container plumbing into a single shared,
# GC-rooted profile that every user can read.
RUN set -eux; \
    nix profile install \
      --profile /nix/var/nix/profiles/agent-tools \
      '.#agent-env' '.#container-tools'

ENV PATH=/nix/var/nix/profiles/agent-tools/bin:$PATH

# Point TLS at the cacert bundle we installed (a GC root, so it survives the
# collect-garbage at the end — unlike the base image's default-profile bundle).
# Fixes curl during the build and gives the agents working TLS at runtime.
ENV NIX_SSL_CERT_FILE=/nix/var/nix/profiles/agent-tools/etc/ssl/certs/ca-bundle.crt \
    SSL_CERT_FILE=/nix/var/nix/profiles/agent-tools/etc/ssl/certs/ca-bundle.crt \
    CURL_CA_BUNDLE=/nix/var/nix/profiles/agent-tools/etc/ssl/certs/ca-bundle.crt

# Materialise the account databases. In the base image these are symlinks into a
# read-only Nix store path, which `shadow` cannot edit in place; copy them to
# real files first. Also provide the conventional shell entry points the base
# image lacks (/bin/sh, /bin/bash, /usr/bin/env), so login shells and
# `#!/usr/bin/env bash` keep working after the garbage-collect below.
RUN set -eux; \
    for f in passwd group shadow; do \
      cp -L "/etc/$f" "/etc/$f.tmp"; rm -f "/etc/$f"; mv "/etc/$f.tmp" "/etc/$f"; \
    done; \
    chmod 644 /etc/passwd /etc/group; chmod 600 /etc/shadow; \
    ln -sf "$(command -v bash)" /bin/bash; \
    ln -sf "$(command -v bash)" /bin/sh; \
    mkdir -p /usr/bin; ln -sf "$(command -v env)" /usr/bin/env

# ── Impure, lockfile-controlled build step ──────────────────────────────────
# Demonstrates the hybrid contract: Nix supplies the base/toolchain, Docker
# performs a networked install at build time. The artifact is pinned by commit
# AND verified by sha256, so the build fails if upstream content ever differs.
ARG GIT_SHORTCUTS_SHA=599e7f6343a80a58ebb1204e305b19e86ce8483e
ARG GIT_SHORTCUTS_SHA256=24aa4bd5c8a6fe1cfda0ac9d51d7a134ca12090200e6892a4075764e935c7ee8
RUN set -eux; \
    mkdir -p /etc/profile.d; \
    url="https://raw.githubusercontent.com/whacked/setup/${GIT_SHORTCUTS_SHA}/bash/git_shortcuts.sh"; \
    curl -fsSL --cacert "$NIX_SSL_CERT_FILE" "$url" -o /etc/profile.d/git_shortcuts.sh; \
    echo "${GIT_SHORTCUTS_SHA256}  /etc/profile.d/git_shortcuts.sh" | sha256sum -c -

# The single non-root user. Default ids 1000:1000 are remapped to the host
# user's ids at container start by the entrypoint. The init files load
# /etc/profile.d/*.sh for both login (.bash_profile) and non-login (.bashrc)
# interactive shells.
RUN set -eux; \
    groupadd --gid 1000 agent; \
    useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash agent; \
    printf '%s\n' \
      'for __f in /etc/profile.d/*.sh; do [ -r "$__f" ] && . "$__f"; done; unset __f' \
      > /home/agent/.bashrc; \
    printf '%s\n' \
      '[ -r /etc/profile ] && . /etc/profile' \
      '[ -r "$HOME/.bashrc" ] && . "$HOME/.bashrc"' \
      > /home/agent/.bash_profile; \
    chown agent:agent /home/agent/.bashrc /home/agent/.bash_profile

# Default bind-mount target.
RUN install -d -o agent -g agent /workspace
WORKDIR /workspace

COPY entrypoint.sh /usr/local/bin/entrypoint
RUN chmod +x /usr/local/bin/entrypoint

# Trim build-only paths (nixpkgs source, the llm-agents eval deps). Plain
# collect-garbage removes only paths unreachable from a GC root; it keeps every
# current profile generation, so `nix` and the base tools survive and remain
# usable at runtime. (Do NOT add -d/--delete-old here: deleting old generations
# orphans the base image's default profile and removes `nix` itself.) Slimming
# further via nix2container/multi-stage is the documented future option.
RUN nix-collect-garbage

# Entrypoint runs as root (PID 1): it aligns `agent` to the host uid/gid, then
# drops to `agent`. Because no USER is set, `docker exec` defaults to root —
# which is exactly how you get a root shell after start.
ENTRYPOINT ["/usr/local/bin/entrypoint"]
CMD ["bash", "-l"]
