{ pkgs ? import <nixpkgs> {}, cpd ? null, tfq ? null }:
let
  # provides "echo-shortcuts"
  nix_shortcuts = import (pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/whacked/setup/ce9fe9be8e42db9ce003772099d08395358efe8c/bash/nix_shortcuts.nix.sh";
    hash = "sha256-uK+Fgwr6iWXbfi/itJGELzkWqGZsQ8HFpfc+ztGSF98=";
  }) { inherit pkgs; };
  gitShortcuts = (builtins.fetchurl {
    url = "https://raw.githubusercontent.com/whacked/setup/599e7f6343a80a58ebb1204e305b19e86ce8483e/bash/git_shortcuts.sh";
    sha256 = "1s3ybj9lwxkm80m8krh0084i5jill7bm37dcl3yirzm6r3alpai4";
  });

  cpdPkg = if cpd != null then cpd
    else (builtins.getFlake "github:whacked/cpd/544740fcaaef8ca474d79f26259b324e1ddabd44").packages.${pkgs.system}.default;

  ## tfq — one binary that supersedes cue, ov, and taskmd. Consumed from its
  ## upstream flake (same pattern as cpd above), so there is no src/vendor hash
  ## to maintain here. https://github.com/whacked/tfq (bundles cuelang; shells to rg).
  ## Override by passing `tfq` (e.g. a local build); otherwise bump the pinned rev.
  tfqPkg = if tfq != null then tfq
    else (builtins.getFlake "github:whacked/tfq/4dd74262e861e284fff3dab27facf2d30f781672").packages.${pkgs.system}.default;

in pkgs.mkShell {
  buildInputs = [
    tfqPkg         # supersedes cue, ov, taskmd
    pkgs.jq        # tfq --json post-processing
    pkgs.ripgrep   # tfq shells to rg for search
    pkgs.nodejs
    cpdPkg
  ];  # join lists with ++

  nativeBuildInputs = [
    gitShortcuts
  ];

  shellHook = nix_shortcuts.shellHook + ''
  '' + ''
    echo-shortcuts ${__curPos.file}
  '';  # join strings with +
}
