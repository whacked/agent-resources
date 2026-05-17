{ pkgs ? import <nixpkgs> {}, cpd ? null }:
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

  ## obsidian-vault from https://github.com/sokojh/obsidian-vault
  ## build currently doesn't work
  # obsidianVault = pkgs.rustPlatform.buildRustPackage {
  #   pname = "obsidian-vault";
  #   version = "0.1.0";
  #   src = pkgs.fetchFromGitHub {
  #     owner = "sokojh";
  #     repo = "obsidian-vault";
  #     rev = "898b890605394ee81ebdb91764c248314628fab5";
  #     hash = "sha256-TsOIIbBdAz/jrw0ohJrbOpNp2L9LZrFH/D4MYRrRyGo=";
  #   };
  #   cargoHash = "sha256-1i9VSR7g0dgyGkEOrFlwQm/moGs3B3t7pFghrBq+ssg=";
  # };
  obsidianVault = pkgs.stdenv.mkDerivation rec {
    pname = "obsidian-vault";
    version = "0.1.0";

    src = pkgs.fetchzip (
      if pkgs.stdenv.isDarwin && pkgs.stdenv.isAarch64 then {
        url = "https://github.com/sokojh/obsidian-vault/releases/download/v${version}/ov-aarch64-apple-darwin.tar.gz";
        hash = "sha256-r/7oBGYzXu4so0Z96BFlHx3G7ZE1jZLu6t0GBtOy94k=";
      } else if pkgs.stdenv.isDarwin then {
        url = "https://github.com/sokojh/obsidian-vault/releases/download/v${version}/ov-x86_64-apple-darwin.tar.gz";
        hash = "sha256-me4V7Kzv5vlw971OeFstBY9RP72pdpx0i40MyEMUTNw=";
      } else {
        # fail
      }
    );

    installPhase = ''
      mkdir -p $out/bin
      cp $src/ov $out/bin/
      chmod +x $out/bin/ov
    '';
  };

  taskmd = pkgs.stdenv.mkDerivation rec {
    pname = "taskmd";
    version = "0.2.5";

    src = pkgs.fetchzip (
      if pkgs.stdenv.isDarwin && pkgs.stdenv.isAarch64 then {
        url = "https://github.com/driangle/taskmd/releases/download/v${version}/taskmd-v${version}-darwin-arm64.tar.gz";
        hash = "sha256-0QXocQ8rlIL4q6sPmKklzh3jLEXJ6mLiIeLXYwUpsqA=";
      } else if pkgs.stdenv.isDarwin then {
        url = "https://github.com/driangle/taskmd/releases/download/v${version}/taskmd-v${version}-darwin-amd64.tar.gz";
        hash = "sha256-fglhQGM9+7ee9UxjgoK1ZQIC3elm6azs2oxsM9JTLJg=";
      } else {
        # fail
      }
    );

    installPhase = ''
      mkdir -p $out/bin
      cp $src/taskmd-* $out/bin/taskmd
      chmod +x $out/bin/taskmd
    '';
  };

in pkgs.mkShell {
  buildInputs = [
    pkgs.cue
    pkgs.jq
    pkgs.ripgrep
    pkgs.nodejs
    cpdPkg
    obsidianVault
    taskmd
  ];  # join lists with ++

  nativeBuildInputs = [
    gitShortcuts
  ];

  shellHook = nix_shortcuts.shellHook + ''
  '' + ''
    echo-shortcuts ${__curPos.file}
  '';  # join strings with +
}
