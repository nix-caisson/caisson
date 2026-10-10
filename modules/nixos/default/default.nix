# SPDX-License-Identifier: MIT
#
# The `default` NixOS module caisson registers. A NixOS configuration
# imports every registered module named `default` unless it passes
# `moduleImports`, so this is what a NixOS configuration gets from
# caisson when it does not select its modules itself.
#
# It holds what a NixOS configuration does for the homes declared
# inside it, in two parts:
#
# - `./caisson/forChildren.nix` gives each of those homes a
#   home-manager module that sets the options of the home that come
#   from the machine.
# - The registered module `home-manager-activation` writes the
#   systemd units that activate those homes on the machine.
#
# Both parts read options of caisson's core module. The core module
# leaves its options out when the library of the evaluation is not a
# caisson composition, so both parts are left out in the same case.
{ closure-lib, mkModule, ... }:
{ lib, ... }:
{
  imports =
    if lib ? caisson && lib ? caisson-core then
      [
        (mkModule ./caisson)
        closure-lib.caisson-core.modules.nixos.home-manager-activation
      ]
    else
      [ ];
}
