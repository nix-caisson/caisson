# SPDX-License-Identifier: MIT
{
  description = "Integration test middle layer for lib closure behavior";

  inputs = {
    deps.url = "path:../../../dependencies";

    parent.url = "path:../../../../";

    nixpkgs.follows = "deps/nixpkgs";
    flake-parts.follows = "deps/flake-parts";
  };

  outputs =
    inputs@{ parent, ... }:
    let
      lib = parent.lib.caisson-core.mkLib {
        inherit inputs;

        modules = lib: {
          flake = {
            default = lib.caisson.flake-parts.mkModule ./modules/flake-parts/default;
          };
        };

        libOverlays = mkLibOverlay: {
          flake-parts = parent.libOverlays.flake-parts;
          default = mkLibOverlay ./lib-overlays/default;
        };
      };
    in
    lib.caisson.flake-parts.mkConfiguration {
      configModule = lib.caisson.flake-parts.mkModule ./configs/flake-parts/middle-flake;
    };
}
