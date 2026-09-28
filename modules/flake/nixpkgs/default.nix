# SPDX-License-Identifier: MIT
#
# The package-set flake module: reifies `caisson.nixpkgs.pkgSets` per
# system over the package overlay registry mkLib holds.
{ mkModule, ... }:
{ ... }:
{
  imports = [
    (mkModule ./caisson)
  ];
}
