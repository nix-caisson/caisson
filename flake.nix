# SPDX-License-Identifier: MIT
#
# The flake-parts caisson top of caisson: the flake-parts configuration
# in configs/flake/caisson, which declares the configuration of what
# caisson exports (configs/structural/impl) and the configuration that
# holds the checks (configs/flake/checks). default.nix is the
# structural caisson top over the configuration of what caisson exports,
# for a reader that is not a flake.
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
    # flake-parts, the source of the flake evaluation of this caisson
    # top. The flake-parts integration calls it with the composed library, so
    # the nixpkgs-lib input of flake-parts only serves this pin's lock.
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs-lib";
  };

  outputs =
    inputs@{ caisson-core, ... }:
    let

      core = caisson-core.lib.caisson-core;

      # The pin readers live in this repository and are read by path: no
      # library exists yet at this point.
      pins = import ./lib-overlays/framework/pins;

      lib = core.mkLib {
        # The flake pin reader: the inputs as the pinned dependencies,
        # and the root from `self`.
        inherit (pins.flake inputs) dependencies root;
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
