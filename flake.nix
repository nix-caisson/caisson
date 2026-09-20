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
    # nixpkgs' lib on its own (the lib directory published as a
    # repository), the source of the nixpkgs-lib part of caisson's own
    # composition.
    nixpkgs-lib.url = "github:nix-community/nixpkgs.lib";
    # flake-parts, the source of this top's flake evaluation. The
    # flake-parts integration calls it with the composed library, so
    # its own nixpkgs-lib input only serves this pin's lock.
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs-lib";
  };

  outputs =
    inputs@{ caisson-core, ... }:
    let

      lib = import ./composition/lib.nix {
        caisson-core = caisson-core.lib.caisson-core;
        inherit inputs;
      };

      flakeOutputs = lib.caisson.flake-parts.mkConfiguration {

        name = "caisson";

        configModule = lib.caisson.flake-parts.mkModule ./configs/flake-parts/caisson;

        moduleImports = modules: [ modules.default ];

      };

    in
    flakeOutputs
    // {
      lib = flakeOutputs.lib // {
        composition = import ./composition {
          caisson-core = caisson-core.lib.caisson-core;
          inherit inputs;
        };
      };
    };

}
