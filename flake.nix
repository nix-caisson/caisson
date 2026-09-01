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

        # The composition machinery, vendored from caisson-core (see
        # vendor/caisson-core/PROVENANCE.md). Its mkLib takes the base
        # library as a plain argument and injects the machinery, the
        # module registry, and the manifest under `caisson-core`.
        caisson-core = import ./vendor/caisson-core/lib;

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
          composition = import ./composition { inherit inputs; };
        };
      }

    );

}
