{ pkgs ? import <nixpkgs> {}, cpd ? null }:
let
  # provides "echo-shortcuts"
  nix_shortcuts = import (pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/whacked/setup/ce9fe9be8e42db9ce003772099d08395358efe8c/bash/nix_shortcuts.nix.sh";
    hash = "sha256-uK+Fgwr6iWXbfi/itJGELzkWqGZsQ8HFpfc+ztGSF98=";
  }) { inherit pkgs; };

  cpdPkg = if cpd != null then cpd
    else (builtins.getFlake "github:whacked/cpd/544740fcaaef8ca474d79f26259b324e1ddabd44").packages.${pkgs.system}.default;

in pkgs.mkShell {
  buildInputs = [
    pkgs.cue
    pkgs.nodejs
    cpdPkg
  ];  # join lists with ++

  nativeBuildInputs = [
  ];

  shellHook = nix_shortcuts.shellHook + ''
  '' + ''
    echo-shortcuts ${__curPos.file}
  '';  # join strings with +
}
