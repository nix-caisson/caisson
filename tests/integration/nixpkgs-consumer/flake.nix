# SPDX-License-Identifier: MIT
{
  description = "Integration test: typical consumer of the nixpkgs flake module";

  inputs = {
    # Standalone equivalent (without shared deps infrastructure):
    #   nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    #   parent.url = "github:nix-caisson/caisson";

    deps.url = "path:../../dependencies";

    parent.url = "path:../../..";

    nixpkgs.follows = "deps/nixpkgs";
  };

  outputs =
    inputs@{ parent, ... }:
    let
      lib = parent.lib.caisson-core.mkLib {
        inherit inputs;
        projects = {
          caisson = parent;
        };
      };
    in
    lib.caisson.mkFlake {
      # The default moduleImports selects every registered flake module,
      # so the nixpkgs machinery arrives through the projects channel.
      configModule = lib.caisson.mkFlakeModule ./configs/flake-parts/nixpkgs-consumer;
    };
}
