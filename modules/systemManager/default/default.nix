# SPDX-License-Identifier: MIT
#
# The `default` system-manager module caisson registers. A
# system-manager configuration imports every registered module named
# `default` unless it passes `moduleImports`, so this is what it gets
# from caisson when it does not select its modules itself.
#
# It holds what a machine running another Linux distribution does for
# the configurations declared inside it, as caisson's `default` NixOS
# module does for a NixOS machine:
#
# - `./caisson/forChildren.nix` gives each home the home-manager module
#   `system-manager-parent` and each hjem configuration the hjem module
#   `system-manager-parent`, which set the options that come from the
#   account of the user on the machine.
# - The registered modules `home-manager-activation` and
#   `hjem-activation`, the same modules a NixOS machine uses, write the
#   systemd units that activate the homes and the hjem configurations
#   when the machine is activated.
# - The registered module `nvf-package` installs the Neovim of each nvf
#   configuration declared inside the machine.
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
        closure-lib.caisson.modules.systemManager.home-manager-activation
        closure-lib.caisson.modules.systemManager.hjem-activation
        closure-lib.caisson.modules.systemManager.nvf-package
      ]
    else
      [ ];
}
