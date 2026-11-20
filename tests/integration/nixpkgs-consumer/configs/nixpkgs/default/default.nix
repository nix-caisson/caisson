# SPDX-License-Identifier: MIT
#
# The `default` package config: unfree packages allowed, and the
# default overlay selection plus the polyfill entry.
{ ... }:
{ lib, ... }:
{
  allowUnfree = true;
  caisson.nixpkgs.overlays = [
    lib.caisson.pkgOverlays.default
    lib.caisson.pkgOverlays.polyfill
  ];
}
