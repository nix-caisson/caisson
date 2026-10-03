# SPDX-License-Identifier: MIT
{
  description = "Integration test: a consumer of a project's package overlays";

  inputs = {
    deps.url = "path:../../../dependencies";

    parent.url = "path:../../../..";
    producer.url = "path:../producer";

    nixpkgs.follows = "deps/nixpkgs";
    flake-parts.follows = "deps/flake-parts";
  };

  outputs =
    inputs@{ parent, producer, ... }:
    let
      core = parent.lib.caisson-core;
      lib = core.mkLib {
        inherit (core.pins.flake inputs) sources root;
        name = "consumer";
        systems = [ "x86_64-linux" ];
        projects = {
          caisson = parent;
          inherit producer;
        };
        pkgOverlays = core.mkPkgOverlays ./pkg-overlays;
        configs = core.mkModules ./configs;
        pkgSets = lib: {
          default = lib.caisson.nixpkgs.mkConfiguration { };
          # Selects the extra entry of the producer by name, in place of
          # the default selection.
          withExtra = lib.caisson.nixpkgs.mkConfiguration {
            configModule =
              { lib, ... }:
              {
                caisson.nixpkgs.overlays = [ lib.caisson.nixpkgs.overlays."producer/extra" ];
              };
          };
        };
      };
    in
    lib.caisson.flake-parts.mkConfiguration {
      configModule = lib.caisson-core.configs.flake.consumer;
    };
}
