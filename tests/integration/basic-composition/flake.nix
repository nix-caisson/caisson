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
      # Create a composed 'lib' using the framework's mkLib
      # Note: parent.lib IS lib.caisson because of how it is exported
      lib = parent.lib.mkLib {
        inherit inputs;
      };

    in
    lib.caisson.mkFlake {
      # Convention: config lives in configs/flake-parts/<name>
      configModule = lib.caisson.mkFlakeModule ./configs/flake-parts/basic-composition;
    };
}
