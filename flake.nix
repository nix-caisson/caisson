# SPDX-License-Identifier: MIT
{

  description = "The foundation framework for composable Nix flakes";

  inputs = {

    nixpkgs-lib.url = "github:NixOS/nixpkgs/nixos-unstable?dir=lib";

    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs-lib";
    flake-parts.url = "github:hercules-ci/flake-parts";

  };

  outputs =
    {
      flake-parts,
      nixpkgs-lib,
      self,
      ...
    }@inputs:
    (

      let

        # We need to hack things to make a bootstrap version of `lib` that
        # we can use to gain access to a version of `lib` that has all of
        # our core overlay applied. We assume that at least the caisson overlay
        # does not have any dependencies on other lib overlays.
        bootLib = (
          nixpkgs-lib.lib.extend
            (import ./lib-overlays/core { inherit inputs; } { closure-inputs = inputs; }).overlay
        );

        lib = bootLib.caisson.mkLib {

          inherit inputs;

          modules = lib: {
            flake = {
              default = lib.caisson.mkFlakeModule ./modules/flake-parts/default;
            };
          };

          libOverlays = mkLibOverlay: {
            default = mkLibOverlay ./lib-overlays/default;
          };

        };

      in
      let

        flakeOutputs = lib.caisson.mkFlake {

          name = "caisson";

          configModule = lib.caisson.mkFlakeModule ./configs/flake-parts/caisson;

          moduleImports = modules: { inherit (modules) default; };

        };

      in
      flakeOutputs
      // {
        lib = flakeOutputs.lib // {
          composition = import ./composition { inherit inputs; };
        };
      }

    );

}
