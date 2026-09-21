# SPDX-License-Identifier: MIT
{
  description = "Minimal consumer test -- no custom modules, overlays, or lib export";

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
      # The flake-parts integration alone, registered by hand: its core
      # module reaches the evaluation through the closure of the
      # overlay, so nothing else is registered or selected.
      lib = parent.lib.caisson-core.mkLib {
        inherit inputs;

        libOverlays = _mkLibOverlay: {
          flake-parts = parent.libOverlays.flake-parts;
        };
      };
    in
    lib.caisson.flake-parts.mkConfiguration {
      configModule = lib.caisson.flake-parts.mkModule ./configs/flake/minimal-consumer;
    };
}
