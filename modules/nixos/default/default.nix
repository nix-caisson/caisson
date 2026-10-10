# SPDX-License-Identifier: MIT
#
# The `default` NixOS module caisson registers. A NixOS configuration
# imports every registered module named `default` unless it passes
# `moduleImports`, so this is what a NixOS configuration gets from
# caisson when it does not select its modules itself.
#
# It holds what a NixOS configuration does for the homes declared
# inside it, in three parts:
#
# - `./caisson/forChildren.nix` gives each of those homes two
#   home-manager modules. The first module sets the options of the
#   home that come from the machine. The second module prints a
#   warning when the home is activated on a machine that differs from
#   the machine the home was built for.
# - The registered module `home-manager-activation` writes the
#   systemd units that activate those homes on the machine.
# - The registered module `home-manager-source-marker` writes a file
#   on the machine. The file names the NixOS configuration the
#   machine is running. The warning of the second module compares
#   against that file.
#
# The parts read options of caisson's core module. The core module
# leaves its options out when the library of the evaluation is not a
# caisson composition, so the parts are left out in the same case.
{ closure-lib, mkModule, ... }:
{ lib, ... }:
{
  imports =
    if lib ? caisson && lib ? caisson-core then
      [
        (mkModule ./caisson)
        closure-lib.caisson-core.modules.nixos.home-manager-activation
        closure-lib.caisson-core.modules.nixos.home-manager-source-marker
      ]
    else
      [ ];
}
