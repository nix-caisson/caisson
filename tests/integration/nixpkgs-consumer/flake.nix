# SPDX-License-Identifier: MIT
{
  description = "Integration test: typical consumer of the nixpkgs flake module";

  inputs = {
    # Standalone equivalent (without shared deps infrastructure):
    #   nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    #   flake-parts.url = "github:hercules-ci/flake-parts";
    #   parent.url = "github:nix-caisson/caisson";

    deps.url = "path:../../dependencies";

    parent.url = "path:../../..";

    nixpkgs.follows = "deps/nixpkgs";
    flake-parts.follows = "deps/flake-parts";
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
    lib.caisson.flake-parts.mkConfiguration {
      # The default moduleImports selects every registered flake module,
      # so the nixpkgs machinery arrives through the projects channel.
      configModule = lib.caisson.flake-parts.mkModule ./configs/flake-parts/nixpkgs-consumer;
    };
}
