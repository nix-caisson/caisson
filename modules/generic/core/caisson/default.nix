# SPDX-License-Identifier: MIT
{ ... }:
{
  imports = [
    ./manifest.nix
    ./configurations.nix
    ./exports.nix
    ./lib.nix
    ./libOverlays.nix
    ./modules.nix
    ./pkgOverlays.nix
  ];
}
