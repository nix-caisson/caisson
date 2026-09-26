# SPDX-License-Identifier: MIT
{
  description = "Minimal consumer test -- no custom modules, and the lib export taking its namespace from the composition";

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

        # The namespace this composition contributes to the composed
        # library. `caisson.lib.export.enabled` publishes the namespace
        # named here, so the `lib` flake output is this overlay's
        # contribution and nothing else.
        namespace = "minimal-consumer";

        libOverlays = mkLibOverlay: {
          flake-parts = parent.libOverlays.flake-parts;
          default = mkLibOverlay ./lib-overlays/default;
        };
      };
    in
    lib.caisson.flake-parts.mkConfiguration {
      configModule = lib.caisson.flake-parts.mkModule ./configs/flake/minimal-consumer;
    };
}
