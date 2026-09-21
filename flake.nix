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

      lib = caisson-core.lib.caisson-core.mkLib {
        inherit inputs;
        systems = import ./systems.nix;
        modules = import ./modules.nix;
        libOverlays = import ./libOverlays.nix;
      };

    in
    lib.caisson.flake-parts.mkConfiguration {

      name = "caisson";

      configModule = lib.caisson.flake-parts.mkModule ./configs/flake-parts/caisson;

      moduleImports = modules: [ modules.default ];

    };

}
