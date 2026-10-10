# SPDX-License-Identifier: MIT
#
# The `caisson.*` part of the default NixOS module.
{ closure-lib, ... }:
{ ... }:
{
  imports = [ (import ./forChildren.nix { inherit closure-lib; }) ];
}
