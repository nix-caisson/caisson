# SPDX-License-Identifier: MIT
{
  description = "Minimal consumer test -- no custom modules, and a lib overlay under the namespace named after the project";

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
      # caisson is listed in `projects`, so its lib overlays and its
      # modules are in the registry of this composition. This flake
      # registers one lib overlay and no modules.
      lib = parent.lib.caisson.mkLib {
        inherit (parent.lib.caisson.pins.flake inputs) sources root;

        projects = {
          caisson = parent;
        };

        # The project's name, also the namespace this composition
        # contributes to the composed library. The `lib` flake output
        # is the composed library, so this overlay's contribution is
        # at `lib.minimal-consumer`.
        name = "minimal-consumer";

        libOverlays = coreLib: {
          default = coreLib.caisson.mkLibOverlay ./lib-overlays/default;
        };
      };
    in
    lib.caisson.flake-parts.mkTopConfiguration {
      configModule = lib.caisson.flake-parts.mkModule ./configs/flake/minimal-consumer;
    };
}
