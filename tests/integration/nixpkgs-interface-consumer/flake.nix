# SPDX-License-Identifier: MIT
{
  description = "Integration test: interface-only nixpkgs consumer";

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
      configModule = lib.caisson.mkFlakeModule ./configs/flake-parts/nixpkgs-interface-consumer;

      # Interface only: the registry option without the package-set
      # machinery.
      moduleImports = modules: [
        modules."caisson/default"
        modules."caisson/nixpkgs-interface"
      ];
    };
}
