# SPDX-License-Identifier: MIT
{
  description = "Integration test: a project whose checks configuration adds dependencies that throw when they are read";

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
        inherit (core.pins.flake inputs) dependencies root;
        name = "producer";
        systems = [ "x86_64-linux" ];
        defaultEcosystemSrc = dependencies: { nixpkgs-lib = dependencies.nixpkgs; };
        projects = {
          caisson = parent;
        };
        libOverlays = lib: lib.caisson.mkLibOverlays ./lib-overlays;
        configs = lib: lib.caisson.mkModules ./configs;
      };
    in
    lib.caisson.flake-parts.mkTopConfiguration { };
}
