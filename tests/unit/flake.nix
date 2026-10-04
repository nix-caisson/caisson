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
    # their composition and never evaluate the parent's outputs
    # (which would force the parent's caisson-core pin).
    parent.url = "path:../..";
    parent.flake = false;

    nixpkgs.follows = "deps/nixpkgs";
    nixpkgs-lib.follows = "deps/nixpkgs-lib";
    flake-parts.follows = "deps/flake-parts";
    nix-unit.follows = "deps/nix-unit";

    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    nix-unit.inputs.nixpkgs.follows = "nixpkgs";
    nix-unit.inputs.flake-parts.follows = "flake-parts";

    # The tests compose with the deps world's caisson-core, not the
    # caisson-core the parent's lock names.
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
      core = inputs.caisson-core.lib.caisson-core;
      lib = core.mkLib {
        inherit (core.pins.flake inputs) sources root;
        defaultEcosystemSrc.nixpkgs-lib = inputs.nixpkgs-lib.outPath;
        # Registered from the parent's source path: a flake cannot
        # reference files outside its tree, and reading the
        # source forces none of the parent's outputs. The overlays
        # and the modules register together, since an overlay
        # registered from its file reads the registry of the
        # composition that registered it (the framework module of
        # its class, `modules.<class>.core`, among others).
        modules = lib: lib.caisson-core.mkModules (parent.outPath + "/modules");
        libOverlays = lib: lib.caisson-core.mkLibOverlays (parent.outPath + "/lib-overlays");
      };
    in
    lib.caisson.flake-parts.mkTopConfiguration {
      configModule = lib.caisson.flake-parts.mkModule ./configs/flake/unit-tests;
    };
}
