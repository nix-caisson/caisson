# SPDX-License-Identifier: MIT
#
# The `default` NixOS module caisson registers. A NixOS configuration
# imports every registered module named `default` unless it passes
# `moduleImports`, so this is what a NixOS configuration gets from
# caisson when it does not select its modules itself.
#
# It holds what a NixOS configuration gives the homes declared inside
# it, in `./caisson/forChildren.nix`.
#
# That file defines options of caisson's core module. The core module
# leaves its options out when the library of the evaluation is not a
# caisson composition, so the file is left out in the same case.
{ mkModule, ... }:
{ lib, ... }:
{
  imports = if lib ? caisson && lib ? caisson-core then [ (mkModule ./caisson) ] else [ ];
}
