# SPDX-License-Identifier: MIT
#
# caisson's flake top: the structural configuration in
# configs/structural/caisson evaluated through flake-parts, which adds
# the checks partition. default.nix is the structural top over the
# same configuration for a reader that is not a flake.
{

  description = "The foundation framework for composable Nix flakes";

  inputs = {
    # The composition machinery: mkLib, the module registry and the
    # manifest under `caisson-core`.
    caisson-core.url = "github:nix-caisson/caisson-core";
    # nixpkgs' lib alone (the lib directory published as a
    # repository), the source of the nixpkgs-lib part of the
    # composition of caisson itself.
    nixpkgs-lib.url = "github:nix-community/nixpkgs.lib";
    # flake-parts, the source of this top's flake evaluation. The
    # flake-parts integration calls it with the composed library, so
    # the nixpkgs-lib input of flake-parts only serves this pin's lock.
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs-lib";
  };

  outputs =
    inputs@{ caisson-core, ... }:
    let

      core = caisson-core.lib.caisson-core;

      # The pin readers live in this tree and are read by path: no
      # library exists yet at this point.
      pins = import ./lib-overlays/framework/pins;

      lib = core.mkLib {
        # The flake pin reader: the inputs as the pinned sources, and
        # the root from `self`.
        inherit (pins.flake inputs) sources root;
        name = "caisson";
        systems = import ./systems.nix;
        modules = lib: lib.caisson-core.mkModules ./modules;
        configs = lib: lib.caisson-core.mkModules ./configs;
        libOverlays = lib: lib.caisson-core.mkLibOverlays ./lib-overlays;
      };

    in
    # The configuration registered under the name the composition
    # declares, configs/flake/caisson.
    lib.caisson.flake-parts.mkTopConfiguration { };

}
