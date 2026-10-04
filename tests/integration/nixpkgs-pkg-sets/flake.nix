# SPDX-License-Identifier: MIT
{
  description = "Integration test: package configs declared on mkLib and built by the nixpkgs integration";

  inputs = {
    deps.url = "path:../../dependencies";

    parent.url = "path:../../..";

    nixpkgs.follows = "deps/nixpkgs";
    flake-parts.follows = "deps/flake-parts";
  };

  outputs =
    inputs@{ parent, ... }:
    let
      core = parent.lib.caisson-core;
      lib = core.mkLib {
        inherit (core.pins.flake inputs) sources root;
        name = "nixpkgs-pkg-sets";
        systems = [ "x86_64-linux" ];
        projects = {
          caisson = parent;
        };
        defaultEcosystemSrc = {
          inherit (inputs) nixpkgs;
        };
        modules = core.mkModules ./modules;
        pkgOverlays = core.mkPkgOverlays ./pkg-overlays;
        # The package configs: `default` takes the default selections,
        # `unfree` selects the registered nixpkgsConfig module as well.
        pkgSets = lib: {
          default = lib.caisson.nixpkgs.mkConfiguration { };
          unfree = lib.caisson.nixpkgs.mkConfiguration {
            moduleImports = registry: [ registry.unfree ];
          };
        };
      };
    in
    lib.caisson.flake-parts.mkTopConfiguration {
      configModule = lib.caisson.flake-parts.mkModule ./configs/flake/nixpkgs-pkg-sets;
    };
}
