# SPDX-License-Identifier: MIT
{ ... }:
{
  imports = [
    ./manifest.nix
    ./configurations.nix
    ./exports.nix
    ./forChildren.nix
    ./forNearestChildren.nix
    ./libOverlays.nix
    ./modules.nix
    ./pkgOverlays.nix
  ];
}
