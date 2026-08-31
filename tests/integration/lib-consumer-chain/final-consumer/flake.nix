# SPDX-License-Identifier: MIT
{
  description = "Integration test final layer for lib closure behavior";

  inputs = {
    deps.url = "path:../../../dependencies";

    parent.url = "path:../../../../";
    middle-flake.url = "path:../middle-flake";

    nixpkgs.follows = "deps/nixpkgs";
    flake-parts.follows = "deps/flake-parts";
  };

  outputs =
    inputs@{
      parent,
      middle-flake,
      ...
    }:
    let
      lib = parent.lib.caisson-core.mkLib {
        inherit inputs;
        libOverlays = _mkLibOverlay: {
          flake-parts = parent.libOverlays.flake-parts;
          middle-chain = middle-flake.libOverlays.default;
        };
      };
    in
    lib.caisson.mkFlake {
      configModule = lib.caisson.mkFlakeModule ./configs/flake-parts/final-consumer;
    };
}
