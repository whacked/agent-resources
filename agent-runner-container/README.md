# agent-runner-container

A Dockerized runner for LLM coding agents, where **Nix owns the build contract**
and **Docker performs the image build**. The agents come from
[`numtide/llm-agents.nix`](https://github.com/numtide/llm-agents.nix); the image
ships with `claude-code`, `codex`, `pi`, and `opencode` by default.

One command takes you from a checkout to a shell inside the container:

```bash
nix run .#up
```

## Prerequisites

- **Nix** with flakes enabled (`experimental-features = nix-command flakes`)
- **Docker** (Docker Desktop on macOS, or the engine on Linux)

No host Linux builder is required: the agents are installed by Nix *inside*
Docker's native-platform build, so this works on Apple Silicon macOS
(`linux/arm64`) and on Linux without cross-compilation.

## Commands

The canonical interface is `nix run .#<app>`; the `Makefile` is thin sugar.

| Command | `make` | What it does |
| --- | --- | --- |
| `nix run .#up` | `make` / `make up` | Build (cached) then drop into the container — the one-shot path |
| `nix run .#build-image` | `make build` | Build `agent-runner:latest` via the Nix-orchestrated Docker build |
| `nix run .#run` | `make run` | Launch the container without rebuilding |
| `nix run .#root` | `make root` | Open a **root** shell in the running container |
| `nix run .#add -- rg fd` | `make add PKG="rg fd"` | Install nixpkgs packages into the running container (ephemeral) |
| `nix run .#test-image` | `make test` | Smoke-test the built image |
| `nix develop` | — | Enter the dev shell |
| — | `make clean` | Remove the image and reclaim **all** build cache |

`nix run .#up` builds with the BuildKit layer cache (fast when nothing changed),
prunes only dangling `<none>` images left by re-tagging, runs the container with
`--rm`, and drops you into a login shell — so a normal run leaves no junk behind.
`make clean` is the heavier reset for when you want the space back.

## Using the container

- You start as the non-root user **`agent`**, in **`/workspace`**.
- `/workspace` is your host `$PWD` by default. Override it:
  ```bash
  WORKSPACE=/path/to/project nix run .#run
  ```
- More mounts, ports, or env vars go through `DOCKER_ARGS` (works with the
  `Makefile`, `nix run .#run`, and `./run.sh`):
  ```bash
  DOCKER_ARGS="-v $HOME/.config/gh:/home/agent/.config/gh -p 8080:8080" nix run .#run
  ```
  Anything beyond that, just `docker run` the image yourself — after a build it
  lives in your local Docker (see *Build-time vs runtime* below).
- The host user's uid/gid are mapped onto `agent` at start, so files you create
  in `/workspace` stay owned by you on the host.
- `host.docker.internal` resolves to the host from inside the container (works on
  Linux too, via `--add-host=host.docker.internal:host-gateway`).
- Need root? The container's foreground process is `agent`, but `docker exec`
  defaults to root:
  ```bash
  docker exec -it agent-runner bash        # root shell
  docker exec -u agent -it agent-runner bash   # agent shell
  ```
- Run a one-off command instead of a shell:
  ```bash
  nix run .#run -- claude --version
  ```

## Changing the agent lineup

Edit the single list in [`flake.nix`](./flake.nix) and rebuild:

```nix
agentNames = [ "claude-code" "codex" "pi" "opencode" ];
```

Browse the 150+ available agents:

```bash
nix eval github:numtide/llm-agents.nix#packages.aarch64-linux --apply builtins.attrNames
```

This list is the single source of truth — it drives the container build (and you
can append the packages to the dev shell to get the agents on your host too).

## Installing more packages

The image is `FROM nixos/nix`, so **Nix is available inside it** and gives you a
150 000+ package set without `apt`. There are two ways to add packages:

**1. Declaratively (recommended — reproducible, persistent).** Add to the env in
`flake.nix` and rebuild. Agents go in `agentNames`; ordinary tools go in
`container-tools`:

```nix
container-tools = pkgs.buildEnv {
  name = "container-tools";
  paths = with pkgs; [ ... fd bat htop ];   # add here
};
```
```bash
nix run .#build-image
```

**2. At runtime (quick, but ephemeral).** While the container is running, install
into the shared profile so it lands on the agent's `PATH` immediately:

```bash
nix run .#add -- fd bat          # or: make add PKG="fd bat"
# under the hood: docker exec -u 0 agent-runner \
#   nix profile install --profile /nix/var/nix/profiles/agent-tools nixpkgs#fd ...
```

Because the launchers run with `--rm`, runtime installs disappear when the
container exits — by design. The store write needs root, which is why this goes
through `docker exec -u 0` (`agent` can *run* `nix` for searching/inspection, but
not write the store). For anything you want to keep, use option 1 and rebuild.

## Build-time vs runtime (what's "nixified")

Per the design, **Nix owns the build; the runtime is a normal Docker image.**
After `nix run .#build-image`, `agent-runner:latest` is in your local Docker and
you can ignore Nix entirely:

```bash
docker run --rm -it -v "$PWD:/workspace" -w /workspace \
  --add-host=host.docker.internal:host-gateway \
  -e HOST_UID=$(id -u) -e HOST_GID=$(id -g) agent-runner:latest
```

The `nix run .#run` / `.#up` apps and `run.sh` are just convenience wrappers
around exactly that command. Nix is still *present in the image* (that's how
runtime installs and the agents' closures work), but you are not required to use
Nix to launch or use the container.

## How the build works

This is a deliberately **hybrid** build (see
[the design report](../artifacts/reports/2026/06/24/2026-06-24.001-agent-runner-container.md)):

1. `nix run .#build-image` is the one entry point used locally and in CI.
2. The image is built `FROM nixos/nix` (pinned by digest). Inside the build,
   Nix installs the agents from the **pinned** `llm-agents.nix` flake
   (`flake.lock`), pulling prebuilt binaries from its cache instead of compiling.
3. An **impure, lockfile-controlled** step then pulls a helper script from GitHub
   — pinned by commit **and** verified by `sha256`, so the build fails if the
   upstream content ever changes. This demonstrates the contract: Nix supplies
   the toolchain; Docker performs the networked install.

### Reproducibility

- `flake.lock` pins `nixpkgs` and `llm-agents.nix`.
- The base image is pinned by digest (`nixos/nix@sha256:…`).
- The impure GitHub pull is pinned by commit and checked against a `sha256`.

The target is an *identically working* image, not a byte-identical tarball.

## Notes & caveats

- **Image size (~4.5 GB).** Nix and the agents' full closures live in the image.
  That is intentional for a dev-runner — you can `nix profile install` more agents
  at runtime. Slimming via `nix2container` / a multi-stage runtime is the
  documented future step, not a v1 requirement.
- **macOS group ownership.** Docker Desktop's file sharing maps the *uid* of
  bind-mounted files to the host user reliably; the *gid* may display differently
  than inside the container. This is a Docker Desktop nuance and does not affect
  single-user workflows. On Linux, both map faithfully.
- **Binary cache.** The build uses `cache.numtide.com`. Inside the Docker build,
  Nix runs as a trusted (root) user, so the cache is honoured. For a fast
  `nix develop` / agents-on-host, add that substituter to your host Nix trust
  settings.
