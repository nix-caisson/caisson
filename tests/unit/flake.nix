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

    # Source-only: the tests register the parent's overlay files into
    # their own composition and never evaluate the parent's outputs
    # (which would force the parent's own caisson-core pin).
    parent.url = "path:../..";
    parent.flake = false;

    nixpkgs.follows = "deps/nixpkgs";
    nixpkgs-lib.follows = "deps/nixpkgs-lib";
    flake-parts.follows = "deps/flake-parts";
    nix-unit.follows = "deps/nix-unit";

    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    nix-unit.inputs.nixpkgs.follows = "nixpkgs";
    nix-unit.inputs.flake-parts.follows = "flake-parts";

    # A downstream that cares which caisson-core composes its library
    # declares its own; this flake does, so the tests are pinned to
    # the deps world's core rather than to caisson's hidden pin.
    caisson-core.follows = "deps/caisson-core";

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
      lib = inputs.caisson-core.lib.caisson-core.mkLib {
        inherit inputs;
        baseLib = inputs.nixpkgs-lib.lib;
        # Registered from the parent's source path: a flake cannot
        # reference files outside its own tree, and reading the
        # source forces none of the parent's outputs.
        libOverlays = mkLibOverlay: {
          flake-parts = mkLibOverlay (parent.outPath + "/lib-overlays/flake-parts");
        };
      };
    in
    lib.caisson.mkFlake {
      configModule = lib.caisson.mkFlakeModule ./configs/flake-parts/unit-tests;
    };
}
