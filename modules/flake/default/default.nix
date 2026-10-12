# SPDX-License-Identifier: MIT
#
# The `default` flake module caisson registers: what every flake
# configuration beneath caisson gets unless it selects otherwise,
# which is the nixpkgs integration's module layer.
{ closure-lib, mkModule, ... }:
{ ... }:
{
  imports = [
    closure-lib.caisson-core.modules.flake.nixpkgs
    (mkModule ./caisson)
  ];
}
