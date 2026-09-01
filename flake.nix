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
      nixpkgs-lib,
      ...
    }@inputs:
    (

      let

        # The composition machinery. Hand-wired evaluations (callFlake
        # in the sandboxed harnesses, the compat shim) inject
        # `caisson-core` beside the declared inputs; everywhere else
        # it is fetched lazily at the hidden pin in
        # caisson-core-pin.nix (see that file for the design). Its
        # mkLib takes the base library as a plain argument and injects
        # the machinery, the module registry, and the manifest under
        # `caisson-core`.
        caisson-core-flake =
          inputs.caisson-core or (
            let
              src = builtins.fetchTree (
                {
                  type = "github";
                  owner = "nix-caisson";
                  repo = "caisson-core";
                }
                // import ./caisson-core-pin.nix
              );
            in
            {
              lib.caisson-core = import (src + "/lib");
              inherit (src) outPath;
            }
          );
        caisson-core = caisson-core-flake.lib.caisson-core;

        lib = caisson-core.mkLib {

          inherit inputs;

          baseLib = nixpkgs-lib.lib;

          modules = composedLib: {
            flake = {
              default = composedLib.caisson.mkFlakeModule ./modules/flake-parts/default;
            };
          };

          libOverlays = mkLibOverlay: {
            flake-parts = mkLibOverlay ./lib-overlays/flake-parts;
            tooling = mkLibOverlay ./lib-overlays/tooling;
            nixpkgs = mkLibOverlay ./lib-overlays/nixpkgs;
            nixos = mkLibOverlay ./lib-overlays/nixos;
            home-manager = mkLibOverlay ./lib-overlays/home-manager;
            colmena = mkLibOverlay ./lib-overlays/colmena;
            terranix = mkLibOverlay ./lib-overlays/terranix;
            system-manager = mkLibOverlay ./lib-overlays/system-manager;
          };

        };

      in
      let

        flakeOutputs = lib.caisson.mkFlake {

          name = "caisson";

          configModule = lib.caisson.mkFlakeModule ./configs/flake-parts/caisson;

          moduleImports = modules: [ modules.default ];

        };

      in
      flakeOutputs
      // {
        lib = flakeOutputs.lib // {
          composition = import ./composition { inherit caisson-core inputs; };
        };
      }

    );

}
