# SPDX-License-Identifier: MIT
{

  description = "The foundation framework for composable Nix flakes";

  inputs = {
    # The composition machinery: mkLib, the module registry and the
    # manifest under `caisson-core`.
    caisson-core.url = "github:nix-caisson/caisson-core";
    # nixpkgs' lib on its own (the lib directory published as a
    # repository), the source of the nixpkgs-lib part of caisson's own
    # composition.
    nixpkgs-lib.url = "github:nix-community/nixpkgs.lib";
    # flake-parts, the source of caisson's own flake evaluation. The
    # flake-parts integration calls it with the composed library, so
    # its own nixpkgs-lib input only serves this pin's lock.
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs-lib";
  };

  outputs =
    inputs@{ caisson-core, ... }:
    (

      let

        lib = caisson-core.lib.caisson-core.mkLib {

          inherit inputs;

          # The platforms this tree builds on, declared once; the core
          # flake-parts module defaults flake-parts' `systems` from it.
          # nixpkgs-lib and flake-parts resolve from the inputs of
          # those names.
          systems = [ "x86_64-linux" ];

          modules = composedLib: {
            flake = {
              default = composedLib.caisson.flake-parts.mkModule ./modules/flake-parts/default;
              # The nixpkgs integration's module layer: the overlay
              # registry (nixpkgs-interface) and the package-set
              # machinery that reifies `caisson.nixpkgs.pkgSets` per
              # system (nixpkgs, which imports the interface).
              nixpkgs = composedLib.caisson.flake-parts.mkModule ./modules/flake-parts/nixpkgs;
              nixpkgs-interface = composedLib.caisson.flake-parts.mkModule ./modules/flake-parts/nixpkgs-interface;
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

        flakeOutputs = lib.caisson.flake-parts.mkConfiguration {

          name = "caisson";

          configModule = lib.caisson.flake-parts.mkModule ./configs/flake-parts/caisson;

          moduleImports = modules: [ modules.default ];

        };

      in
      flakeOutputs
      // {
        lib = flakeOutputs.lib // {
          composition = import ./composition {
            caisson-core = caisson-core.lib.caisson-core;
            inherit inputs;
          };
        };
      }

    );

}
