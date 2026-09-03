# SPDX-License-Identifier: MIT
{
  description = "Integration test: nixpkgs flake module with no package sets";

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
      # The default moduleImports applies the nixpkgs machinery through
      # the projects channel; this flake configures none of it.
      configModule = lib.caisson.mkFlakeModule ./configs/flake-parts/nixpkgs-no-pkg-sets;
    };
}
