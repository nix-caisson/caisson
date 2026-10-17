# SPDX-License-Identifier: MIT
#
# The `default` NixOS module caisson registers. A NixOS configuration
# imports every registered module named `default` unless it passes
# `moduleImports`, so this is what a NixOS configuration gets from
# caisson when it does not select its modules itself.
#
# `./networking` defaults the host name of the NixOS configuration to
# the name it is declared under, at `mkDefault` priority.
#
# The registered module `hjem-activation` activates the hjem
# configurations declared inside the machine, and
# `./caisson/forChildren.nix` gives each of them the hjem module
# `nixos-parent`, which sets the user's home directory from the
# machine's account.
#
# It also holds what a NixOS configuration does for the homes declared
# inside it, in two parts:
#
# - `./caisson/forChildren.nix` gives each of those homes the
#   home-manager module `nixos-parent`, which sets the options of the
#   home that come from the machine.
# - The registered module `home-manager-activation` writes the
#   systemd units that activate those homes on the machine.
#
# The registered module `activation-marker` writes a file on the
# machine that names what the machine applied. Every configuration with
# an activation declared inside the machine, a home among them, compares
# against that file when it is activated by hand, and warns when it was
# built for a different machine.
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
        (mkModule ./networking)
        (mkModule ./caisson)
        closure-lib.caisson.modules.nixos.home-manager-activation
        closure-lib.caisson.modules.nixos.hjem-activation
        closure-lib.caisson.modules.nixos.nvf-package
        closure-lib.caisson.modules.nixos.activation-marker
      ]
    else
      [ ];
}
