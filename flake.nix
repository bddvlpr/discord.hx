{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixpkgs-unstable";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    crane.url = "github:ipetkov/crane";

    advisory-db = {
      url = "github:rustsec/advisory-db";
      flake = false;
    };
  };

  outputs =
    {
      flake-parts,
      crane,
      advisory-db,
      ...
    }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      perSystem =
        { self', pkgs, ... }:
        let
          craneLib = crane.mkLib pkgs;
          src = craneLib.cleanCargoSource ./.;

          commonArgs = {
            inherit src;
            strictDeps = true;
          };

          cargoArtifacts = craneLib.buildDepsOnly commonArgs;

          discord-hx = craneLib.buildPackage (
            commonArgs
            // {
              inherit cargoArtifacts;
              postInstall = ''
                mkdir -p "$out/share/discord-hx"
                cp ${./discord.scm} "$out/share/discord-hx/discord.scm"
              '';
            }
          );
        in
        {
          checks = {
            inherit discord-hx;

            discord-hx-clippy = craneLib.cargoClippy (
              commonArgs
              // {
                inherit cargoArtifacts;
                cargoClippyExtraArgs = "--all-targets -- --deny warnings";
              }
            );

            discord-hx-fmt = craneLib.cargoFmt { inherit src; };

            discord-hx-toml-fmt = craneLib.taploFmt {
              src = pkgs.lib.sources.sourceFilesBySuffices src [ ".toml" ];
            };

            discord-hx-audit = craneLib.cargoAudit {
              inherit src advisory-db;
            };

            discord-hx-deny = craneLib.cargoDeny {
              inherit src;
            };
          };

          packages = {
            inherit discord-hx;
            default = discord-hx;
          };

          devShells.default = craneLib.devShell {
            checks = self'.checks;
          };
        };
    };
}
