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
      lib = parent.lib.caisson.mkLib {
        inherit (parent.lib.caisson.pins.flake inputs) sources root;
        defaultEcosystemSrc = sources: { nixpkgs-lib = sources.nixpkgs; };
        name = "final-consumer";
        projects = {
          caisson = parent;
          middle-chain = middle-flake;
        };
      };
    in
    lib.caisson.flake-parts.mkTopConfiguration {
      configModule = lib.caisson.flake-parts.mkModule ./configs/flake/final-consumer;
    };
}
