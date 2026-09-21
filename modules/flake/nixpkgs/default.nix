# SPDX-License-Identifier: MIT
#
# The package-set flake module: the option declarations of the
# interface module (the `nixpkgs-interface` registry entry, reached
# through the closure) plus the implementation that reifies
# `caisson.nixpkgs.pkgSets` per system.
{ closure-lib, mkModule, ... }:
{ ... }:
{
  imports = [
    closure-lib.caisson-core.modules.flake.nixpkgs-interface
    (mkModule ./caisson)
  ];
}
