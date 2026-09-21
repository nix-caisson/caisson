# SPDX-License-Identifier: MIT
{
  description = "Basic composition test for caisson";

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
    inputs@{
      self,
      nixpkgs,
      flake-parts,
      parent,
      ...
    }:
    let
      # Compose a library with mkLib. parent.lib mirrors the framework
      # namespaces of the composed library (`caisson`, `caisson-core`).
      lib = parent.lib.caisson-core.mkLib {
        inherit inputs;
        libOverlays = _mkLibOverlay: {
          flake-parts = parent.libOverlays.flake-parts;
        };
      };

    in
    lib.caisson.flake-parts.mkConfiguration {
      # Convention: config lives in configs/<class>/<name>
      configModule = lib.caisson.flake-parts.mkModule ./configs/flake/basic-composition;
    };
}
