# SPDX-License-Identifier: MIT
#
# The `withExtra` package config: the extra entry of the producer,
# selected by name in place of the default selection.
{ ... }:
{ lib, ... }:
{
  caisson.nixpkgs.overlays = [ lib.caisson.pkgOverlays."producer/extra" ];
}
