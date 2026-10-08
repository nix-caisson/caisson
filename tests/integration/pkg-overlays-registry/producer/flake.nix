# SPDX-License-Identifier: MIT
{
  description = "Integration test: a project that registers package overlays";

  inputs = {
    deps.url = "path:../../../dependencies";

    parent.url = "path:../../../..";

    nixpkgs.follows = "deps/nixpkgs";
    flake-parts.follows = "deps/flake-parts";
  };

  outputs =
    inputs@{ parent, ... }:
    let
      core = parent.lib.caisson;
      lib = core.mkLib {
        inherit (core.pins.flake inputs) sources root;
        name = "producer";
        systems = [ "x86_64-linux" ];
        projects = {
          caisson = parent;
        };
        pkgOverlays = lib: lib.caisson.mkPkgOverlays ./pkg-overlays;
        modules = lib: lib.caisson.mkModules ./modules;
        configs = lib: lib.caisson.mkModules ./configs;
        pkgSets = lib: lib.caisson.nixpkgs.mkConfigurations { };
      };
    in
    lib.caisson.flake-parts.mkTopConfiguration {
      configModule = lib.caisson.configs.flake.producer;
    };
}
