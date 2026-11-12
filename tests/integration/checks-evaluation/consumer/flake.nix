# SPDX-License-Identifier: MIT
{
  description = "Integration test: a consumer of a project whose checks configuration adds dependencies";

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
      core = parent.lib.caisson;
      lib = core.mkLib {
        inherit (core.pins.flake inputs) dependencies root;
        name = "consumer";
        systems = [ "x86_64-linux" ];
        defaultEcosystemSrc = dependencies: { nixpkgs-lib = dependencies.nixpkgs; };
        projects = {
          caisson = parent;
          inherit producer;
        };
        configs = lib: lib.caisson.mkModules ./configs;
      };
    in
    lib.caisson.flake-parts.mkTopConfiguration { };
}
