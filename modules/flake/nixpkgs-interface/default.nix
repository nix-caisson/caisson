# SPDX-License-Identifier: MIT
# Option declarations only: the `caisson.nixpkgs.*` options a sibling
# flake module may set without pulling in package-set reification. The
# nixpkgs flake module imports this and adds the implementation.
{ mkModule, ... }:
{ ... }:
{
  imports = [ (mkModule ./caisson) ];
}
