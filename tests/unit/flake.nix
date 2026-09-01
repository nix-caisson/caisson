# SPDX-License-Identifier: MIT
{
  description = "Unit tests for caisson library overlays";

  inputs = {
    # Standalone equivalent (without shared deps infrastructure):
    #   nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    #   nixpkgs-lib.url = "github:nix-community/nixpkgs.lib";
    #   flake-parts.url = "github:hercules-ci/flake-parts";
    #   nix-unit.url = "github:nix-community/nix-unit";
    #   parent.url = "github:nix-caisson/caisson";

    deps.url = "path:../dependencies";

    parent.url = "path:../..";

    nixpkgs.follows = "deps/nixpkgs";
    nixpkgs-lib.follows = "deps/nixpkgs-lib";
    flake-parts.follows = "deps/flake-parts";
    nix-unit.follows = "deps/nix-unit";

    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    nix-unit.inputs.nixpkgs.follows = "nixpkgs";
    nix-unit.inputs.flake-parts.follows = "flake-parts";

    parent-flake-parts.follows = "parent/flake-parts";

    parent-caisson-core.follows = "parent/caisson-core";

  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-parts,
      nix-unit,
      parent,
      ...
    }:
    let
      lib = parent.lib.caisson-core.mkLib {
        inherit inputs;
        libOverlays = _mkLibOverlay: {
          flake-parts = parent.libOverlays.flake-parts;
        };
      };
    in
    lib.caisson.mkFlake {
      configModule = lib.caisson.mkFlakeModule ./configs/flake-parts/unit-tests;
    };
}
