# SPDX-License-Identifier: MIT
{
  description = "Integration test: nixpkgs overlay export";

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
        inherit (parent.lib.caisson-core.pins.flake inputs) sources root;
        name = "nixpkgs-overlay-export";
        systems = [ "x86_64-linux" ];
        projects = {
          caisson = parent;
        };
        pkgOverlays = parent.lib.caisson-core.mkPkgOverlays ./pkg-overlays;
        pkgSets = lib: { default = lib.caisson.nixpkgs.mkConfiguration { }; };
      };
    in
    lib.caisson.flake-parts.mkConfiguration {
      configModule = lib.caisson.flake-parts.mkModule ./configs/flake/nixpkgs-overlay-export;
    };
}
