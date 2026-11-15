# SPDX-License-Identifier: MIT
#
# The `default` hjem module caisson registers. A hjem configuration
# imports every registered module named `default` unless it passes
# `moduleImports`, so this is what it gets from caisson when it does not
# select its modules itself:
#
# - `profile-activation`, which puts the `bin` directory of the profile
#   of each nvf, nixvim or nemacs configuration declared inside the hjem
#   configuration on `PATH`, where the NixOS, nix-darwin or
#   system-manager configuration above activates the profile;
# - `activation-marker`, which records what the hjem configuration
#   applied, for the configurations declared inside it to check.
{ closure-lib, ... }:
{ ... }:
{
  imports = [
    closure-lib.caisson.modules.hjem.profile-activation
    closure-lib.caisson.modules.hjem.activation-marker
  ];
}
