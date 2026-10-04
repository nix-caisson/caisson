# SPDX-License-Identifier: MIT
#
# The `withAdded` package config: the extra entry of the producer,
# added to the default selection.
{ ... }:
{ lib, ... }:
{
  caisson.nixpkgs.extraOverlays = [ lib.caisson.nixpkgs.overlays."producer/extra" ];
}
