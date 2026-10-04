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
        inherit (parent.lib.caisson-core.pins.flake inputs) sources root;
        name = "final-consumer";
        libOverlays = _mkLibOverlay: {
          flake-parts = parent.libOverlays.flake-parts;
          middle-chain = middle-flake.libOverlays.default;
        };
      };
    in
    lib.caisson.flake-parts.mkTopConfiguration {
      configModule = lib.caisson.flake-parts.mkModule ./configs/flake/final-consumer;
    };
}
