# SPDX-License-Identifier: MIT
#
# The `default` system-manager module caisson registers. A
# system-manager configuration imports every registered module named
# `default` unless it passes `moduleImports`, so this is what it gets
# from caisson when it does not select its modules itself.
#
# It holds what a system-manager configuration does for the
# configurations declared inside it, as caisson's `default` NixOS
# module does for a NixOS configuration:
#
# - `./caisson/forChildren.nix` gives each home-manager configuration
#   the home-manager module `nixos-parent` and each hjem
#   configuration the hjem module `nixos-parent`, which set
#   the options that come from the account of the user that the
#   system-manager configuration declares.
# - The registered modules `home-manager-activation` and
#   `hjem-activation`, the same modules a NixOS configuration uses,
#   write the systemd units that activate the home-manager
#   configurations and the hjem configurations when the system-manager
#   configuration is activated.
# - The registered module `profile-activation`, the same module a NixOS
#   configuration uses, activates the profile of each nvf or nixvim
#   configuration declared inside the system-manager configuration, and
#   lets a shell choose among them.
# - The registered module `activation-marker` records what the
#   system-manager configuration applied, for the configurations
#   declared inside it to check for drift.
#
# The parts read options of caisson's core module. The core module
# leaves its options out when the library of the configuration is not a
# caisson composition, so the parts are left out in the same case.
{ closure-lib, mkModule, ... }:
{ lib, ... }:
{
  imports =
    if lib ? caisson && lib ? caisson-core then
      [
        (mkModule ./caisson)
        closure-lib.caisson.modules.generic.home-manager-activation
        closure-lib.caisson.modules.generic.hjem-activation
        closure-lib.caisson.modules.generic.profile-activation
        closure-lib.caisson.modules.generic.activation-marker
      ]
    else
      [ ];
}
