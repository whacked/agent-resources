{
  description = "agent-runner — Nix-orchestrated, Docker-built LLM agent runner";

  # llm-agents.nix serves its builds from this cache, so the image build pulls
  # binaries instead of compiling. nixConfig applies to the top-level flake, so
  # we declare it here (the Dockerfile also writes it into the build's nix.conf).
  nixConfig = {
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [ "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=" ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    llm-agents.url = "github:numtide/llm-agents.nix";
  };

  outputs = { self, nixpkgs, flake-utils, llm-agents }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # ───────────────────────────────────────────────────────────────────
        #  EDIT HERE — the agents baked into the container image.
        #
        #  Each entry must be a package name in `llm-agents.packages.<system>`.
        #  Browse the full catalogue (150+ agents) with:
        #
        #    nix eval github:numtide/llm-agents.nix#packages.${system} \
        #      --apply builtins.attrNames
        #
        #  This list is the single source of truth: it drives the image build
        #  below and (optionally) the dev shell. Add/remove a name, rebuild.
        # ───────────────────────────────────────────────────────────────────
        agentNames = [ "claude-code" "codex" "pi" "opencode" ];

        agentPkgs = map (name: llm-agents.packages.${system}.${name}) agentNames;

        # The agent layer the Dockerfile installs (one merged env on PATH).
        agent-env = pkgs.buildEnv {
          name = "agent-env";
          paths = agentPkgs;
        };

        # Container plumbing — NOT agents. User management (shadow), privilege
        # drop (gosu), a real interactive shell, TLS roots, and the tools the
        # impure build step + entrypoint rely on.
        container-tools = pkgs.buildEnv {
          name = "container-tools";
          paths = with pkgs; [
            bashInteractive coreutils gnugrep gnused findutils which
            shadow gosu cacert curl git jq ripgrep
          ];
        };

        image = "agent-runner:latest";

        # docker is supplied by the host (Docker Desktop / engine), matching the
        # directive's baseline of "a machine with nix and docker installed".
        dockerCheck = ''
          if ! command -v docker >/dev/null 2>&1; then
            echo "error: 'docker' not found on PATH — Docker Desktop / engine is required" >&2
            exit 127
          fi
        '';

        # Resolve the project directory (where the Dockerfile / run.sh live).
        # The apps are meant to be invoked from the agent-runner-container dir
        # via `nix run .#<app>`, so $PWD is that directory.
        projectGuard = file: ''
          if [ ! -f "''${PWD}/${file}" ]; then
            echo "error: ${file} not found in ''${PWD}" >&2
            echo "       run this from the agent-runner-container directory." >&2
            exit 1
          fi
        '';

        build-image = pkgs.writeShellApplication {
          name = "build-image";
          text = ''
            ${dockerCheck}
            ${projectGuard "Dockerfile"}
            echo ">> building ${image}"
            DOCKER_BUILDKIT=1 docker build --tag ${image} "''${PWD}"
            # Drop only dangling (<none>) images orphaned by re-tagging. The
            # BuildKit layer cache is kept, so the next build stays fast — that
            # cache is not "junk", it is what makes rebuilds cheap.
            docker image prune --force >/dev/null 2>&1 || true
            echo ">> built ${image}"
          '';
        };

        run-image = pkgs.writeShellApplication {
          name = "run-image";
          text = ''
            ${dockerCheck}
            ${projectGuard "run.sh"}
            exec bash "''${PWD}/run.sh" "$@"
          '';
        };

        # One command, CLI → container: build (cached), prune dangling, attach.
        up = pkgs.writeShellApplication {
          name = "up";
          text = ''
            ${dockerCheck}
            ${projectGuard "Dockerfile"}
            ${projectGuard "run.sh"}
            "${build-image}/bin/build-image"
            exec bash "''${PWD}/run.sh" "$@"
          '';
        };

        # Open a root shell in the already-running container.
        root-shell = pkgs.writeShellApplication {
          name = "root-shell";
          text = ''
            ${dockerCheck}
            exec docker exec -u 0 -it "''${AGENT_RUNNER_NAME:-agent-runner}" bash -l
          '';
        };

        # Install nixpkgs packages into the RUNNING container's shared profile,
        # so they appear on the agent's PATH immediately. This is ephemeral: a
        # `--rm` container loses it on exit. For persistence, add the package to
        # the flake and rebuild.
        add-pkg = pkgs.writeShellApplication {
          name = "add-pkg";
          text = ''
            ${dockerCheck}
            if [ "$#" -eq 0 ]; then
              echo "usage: nix run .#add -- <pkg> [pkg...]   (nixpkgs attribute names)" >&2
              echo "       e.g. nix run .#add -- ripgrep fd   (ephemeral; rebuild to persist)" >&2
              exit 1
            fi
            name="''${AGENT_RUNNER_NAME:-agent-runner}"
            attrs=(); for p in "$@"; do attrs+=("nixpkgs#$p"); done
            echo ">> installing into running container '$name' (ephemeral): $*"
            exec docker exec -u 0 "$name" \
              nix --extra-experimental-features 'nix-command flakes' \
              profile install --profile /nix/var/nix/profiles/agent-tools "''${attrs[@]}"
          '';
        };

        test-image = pkgs.writeShellApplication {
          name = "test-image";
          text = ''
            ${dockerCheck}
            echo ">> smoke-testing ${image}"
            fail=0

            # 1) Each configured agent is on PATH inside the container.
            for cmd in claude codex pi opencode; do
              if docker run --rm ${image} bash -lc "command -v $cmd" >/dev/null 2>&1; then
                echo "  ok   agent: $cmd"
              else
                echo "  FAIL agent: $cmd not found on PATH"; fail=1
              fi
            done

            # 2) The impure GitHub-pulled script is present and pinned.
            if docker run --rm ${image} \
                 sha256sum /etc/profile.d/git_shortcuts.sh 2>/dev/null \
                 | grep -q '24aa4bd5c8a6fe1cfda0ac9d51d7a134ca12090200e6892a4075764e935c7ee8'; then
              echo "  ok   impure: pinned git_shortcuts.sh present"
            else
              echo "  FAIL impure: git_shortcuts.sh missing or hash mismatch"; fail=1
            fi

            # 3) uid remap: agent inside maps to the requested host uid/gid.
            out="$(docker run --rm -e HOST_UID=4242 -e HOST_GID=4242 ${image} \
                     bash -lc 'id -u; id -un')"
            if printf '%s' "$out" | grep -qx 4242 && printf '%s' "$out" | grep -qx agent; then
              echo "  ok   uid remap: agent -> 4242"
            else
              echo "  FAIL uid remap: got [$out]"; fail=1
            fi

            if [ "$fail" -eq 0 ]; then echo ">> all smoke tests passed"; else
              echo ">> smoke tests FAILED" >&2; exit 1; fi
          '';
        };

        mkApp = drv: { type = "app"; program = "${drv}/bin/${drv.name}"; };
      in
      {
        packages = {
          inherit agent-env container-tools;
          default = agent-env;
        };

        apps = {
          build-image = mkApp build-image;
          run = mkApp run-image;
          up = mkApp up;
          root = mkApp root-shell;
          add = mkApp add-pkg;
          test-image = mkApp test-image;
          default = mkApp up;
        };

        devShells.default = pkgs.mkShell {
          # The dev shell only needs to drive the image build — the agents
          # themselves live in the container. (You can append `agentPkgs` here
          # to also get them on the host; requires the llm-agents binary cache.)
          packages = with pkgs; [ git jq ];
          shellHook = ''
            echo "agent-runner dev shell"
            echo "  nix run .#build-image   # build agent-runner:latest"
            echo "  nix run .#up            # build (cached) + drop into the container"
            echo "  nix run .#run           # launch the container (no rebuild)"
            echo "  nix run .#root          # root shell in the running container"
            echo "  nix run .#add -- rg fd  # install pkgs into the running container (ephemeral)"
            echo "  nix run .#test-image    # smoke test the image"
          '';
        };
      });
}
