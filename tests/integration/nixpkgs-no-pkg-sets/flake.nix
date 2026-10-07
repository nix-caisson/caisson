# SPDX-License-Identifier: MIT
{
  description = "Integration test: nixpkgs flake module with no package sets";

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
      lib = parent.lib.caisson.mkLib {
        inherit (parent.lib.caisson.pins.flake inputs) sources root;
        projects = {
          caisson = parent;
        };
      };
    in
    lib.caisson.flake-parts.mkTopConfiguration {
      # The default default applies caisson/default, which carries the
      # nixpkgs machinery through the projects channel; this flake
      # configures none of it.
      configModule = lib.caisson.flake-parts.mkModule ./configs/flake/nixpkgs-no-pkg-sets;
    };
}
