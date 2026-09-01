# SPDX-License-Identifier: MIT
{

  description = "The foundation framework for composable Nix flakes";

  outputs =
    inputs:
    (

      let

        # caisson declares no flake inputs; the three trees its own
        # evaluation composes with are fetched lazily at the pins in
        # pins.nix (see that file for the design). A hand-wired
        # evaluation (callFlake in the sandboxed harnesses, the
        # compat shim) may inject any of them beside `self`; the
        # injected value wins and nothing fetches.
        pins = import ./pins.nix;
        fetchPin = name: builtins.fetchTree ({ type = "github"; } // pins.${name});

        # The composition machinery. Its mkLib takes the base library
        # as a plain argument and injects the machinery, the module
        # registry, and the manifest under `caisson-core`.
        caisson-core-flake =
          inputs.caisson-core or (
            let
              src = fetchPin "caisson-core";
            in
            {
              lib.caisson-core = import (src + "/lib");
              inherit (src) outPath;
            }
          );
        caisson-core = caisson-core-flake.lib.caisson-core;

        callFlake = import (caisson-core-flake.outPath + "/lib/kernel/call-flake.nix");

        nixpkgs-lib-flake =
          inputs.nixpkgs-lib or (
            let
              src = fetchPin "nixpkgs";
            in
            {
              lib = import (src + "/lib");
              outPath = src + "/lib";
            }
          );

        flake-parts-flake =
          inputs.flake-parts or (callFlake {
            src = fetchPin "flake-parts";
            inputs = {
              nixpkgs-lib = nixpkgs-lib-flake;
            };
          });

        # What registered files close over: the constructed trees
        # under the names the integrations read.
        effectiveInputs = {
          inherit (inputs) self;
          nixpkgs-lib = nixpkgs-lib-flake;
          flake-parts = flake-parts-flake;
        };

        lib = caisson-core.mkLib {

          inputs = effectiveInputs;

          baseLib = nixpkgs-lib-flake.lib;

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
          composition = import ./composition {
            inherit caisson-core;
            inputs = effectiveInputs;
          };
        };
      }

    );

}
