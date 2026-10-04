# SPDX-License-Identifier: MIT
{
  description = "Integration test: typical consumer of the nixpkgs flake module";

  inputs = {
    # Standalone equivalent (without shared deps infrastructure):
    #   nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    #   flake-parts.url = "github:hercules-ci/flake-parts";
    #   parent.url = "github:nix-caisson/caisson";

    deps.url = "path:../../dependencies";

    parent.url = "path:../../..";

    nixpkgs.follows = "deps/nixpkgs";
    flake-parts.follows = "deps/flake-parts";
  };

  outputs =
    inputs@{ parent, ... }:
    let
      lib = parent.lib.caisson-core.mkLib {
        inherit (parent.lib.caisson-core.pins.flake inputs) sources root;
        # The name this flake holds: its package scope lands at
        # `pkgs.nixpkgs-consumer` because of this declaration.
        name = "nixpkgs-consumer";
        systems = [ "x86_64-linux" ];
        projects = {
          caisson = parent;
        };
        pkgOverlays = parent.lib.caisson-core.mkPkgOverlays ./pkg-overlays;
        configs = parent.lib.caisson-core.mkModules ./configs;
        # `default` finds its module by name, configs/nixpkgsConfig/default;
        # `slim` has none registered and applies the default selection
        # alone; `explicit` names the `default` configuration as its
        # module.
        pkgSets = lib: {
          default = lib.caisson.nixpkgs.mkConfiguration { };
          slim = lib.caisson.nixpkgs.mkConfiguration { };
          explicit = lib.caisson.nixpkgs.mkConfiguration {
            configModule = lib.caisson-core.configs.nixpkgsConfig.default;
          };
        };
      };
    in
    lib.caisson.flake-parts.mkTopConfiguration {
      # The default default applies caisson/default, which carries the
      # nixpkgs machinery, so it arrives through the projects channel.
      configModule = lib.caisson.flake-parts.mkModule ./configs/flake/nixpkgs-consumer;
    };
}
