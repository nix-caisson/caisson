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
      lib = parent.lib.caisson.mkLib {
        inherit (parent.lib.caisson.pins.flake inputs) sources root;

        libOverlays = _lib: {
          flake-parts = parent.libOverlays.flake-parts;
        };

        modules = lib: {
          "test-class" = {
            exported = lib.caisson.mkModule "test-class" (
              { ... }:
              {
                exports.testClass.usable = true;
              }
            );
          };
          "disabled-class" = {
            hidden = lib.caisson.mkModule "disabled-class" (
              { ... }:
              {
                exports.disabledClass.shouldBeHidden = true;
              }
            );
          };
        };
      };
    in
    lib.caisson.flake-parts.mkTopConfiguration {
      configModule = lib.caisson.flake-parts.mkModule ./configs/flake/module-class-export;
    };
}
