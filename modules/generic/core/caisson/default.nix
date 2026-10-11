# SPDX-License-Identifier: MIT
{ ... }:
{
  imports = [
    ./manifest.nix
    ./configurations.nix
    ./exports.nix
    ./forChildren.nix
    ./libOverlays.nix
    ./modules.nix
    ./pkgOverlays.nix
  ];
}
