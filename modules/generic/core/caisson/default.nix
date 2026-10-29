# SPDX-License-Identifier: MIT
{ ... }:
{
  imports = [
    ./manifest.nix
    ./configurations.nix
    ./exports.nix
    ./forChildren.nix
    ./forDirectChildren.nix
    ./forNearestChildren.nix
    ./libOverlays.nix
    ./modules.nix
    ./pkgOverlays.nix
  ];
}
