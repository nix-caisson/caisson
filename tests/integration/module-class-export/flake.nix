# SPDX-License-Identifier: MIT
{
  description = "Integration test for generic module class export";

  inputs = {
    deps.url = "path:../../dependencies";

    parent.url = "path:../../..";

    nixpkgs.follows = "deps/nixpkgs";
    flake-parts.follows = "deps/flake-parts";
  };

  outputs =
    inputs@{ parent, ... }:
    let
      lib = parent.lib.caisson-core.mkLib {
        inherit inputs;

        libOverlays = _mkLibOverlay: {
          flake-parts = parent.libOverlays.flake-parts;
        };

        modules = lib: {
          "test-class" = {
            exported = lib.caisson-core.mkModule "test-class" (
              { ... }:
              {
                exports.testClass.usable = true;
              }
            );
          };
          "disabled-class" = {
            hidden = lib.caisson-core.mkModule "disabled-class" (
              { ... }:
              {
                exports.disabledClass.shouldBeHidden = true;
              }
            );
          };
        };
      };
    in
    lib.caisson.mkFlake {
      configModule = lib.caisson.mkFlakeModule ./configs/flake-parts/module-class-export;
    };
}
