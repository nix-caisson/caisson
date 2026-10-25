# SPDX-License-Identifier: MIT
#
# A guest kind of the registered world: the NixOS configuration each
# slot of the kind `microvm-slot` takes, and the configuration
# `microvm-reset` takes too. microvm.nix's guest module, which caisson's
# `microvm-guest` NixOS module imports, gives a guest its boot and file
# systems.
{ ... }:
{ ... }:
{
  system.stateVersion = "25.05";
}
