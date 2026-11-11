# SPDX-License-Identifier: MIT
#
# The `default` flake module caisson registers: what a flake
# configuration composed with caisson gets unless it passes
# `moduleImports`, which is the nixpkgs integration's module layer.
{ closure-lib, mkModule, ... }:
{ ... }:
{
  imports = [
    closure-lib.caisson.modules.flake.nixpkgs
    (mkModule ./caisson)
  ];
}
