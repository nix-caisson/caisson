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

        # The name this flake holds, deliberately not the directory
        # name: the final consumer registers this composition's exported
        # overlay under the same string, so the two halves of the chain
        # agree on a name neither derives from a path.
        namespace = "middle-chain";

        modules = lib: {
          flake = {
            default = lib.caisson.flake-parts.mkModule ./modules/flake/default;
          };
        };

        libOverlays = mkLibOverlay: {
          flake-parts = parent.libOverlays.flake-parts;
          default = mkLibOverlay ./lib-overlays/default;
        };
      };
    in
    lib.caisson.flake-parts.mkConfiguration {
      configModule = lib.caisson.flake-parts.mkModule ./configs/flake/middle-flake;
    };
}
