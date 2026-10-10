# SPDX-License-Identifier: MIT
#
# The `default` home-manager module caisson registers. A home imports
# every registered module named `default` unless it passes
# `moduleImports`, so this is what a home gets from caisson when it
# does not select its modules itself.
#
# It holds one thing. A home that is declared inside a NixOS
# configuration imports the module `nixos-parent`, which sets the
# options of the home that come from the machine: the home directory
# and the user ID of the account, and the Nix of the machine. A home
# with no NixOS configuration above it imports nothing here.
#
# A home takes this module out by passing `moduleImports`. It can then
# list `nixos-parent` itself, or leave it out and set those options
# another way.
#
# The test below reads the manifest of the home through `lib`. In a
# home whose library is not a caisson composition, the test is false.
# home-manager's NixOS module evaluates the homes it embeds on such a
# library.
{ closure-lib, ... }:
{ lib, ... }:
let
  insideAMachine = lib ? caisson && (lib.caisson.evalManifest.nearest or { }) ? nixos;
in
{
  imports =
    if insideAMachine then [ closure-lib.caisson-core.modules.homeManager.nixos-parent ] else [ ];
}
