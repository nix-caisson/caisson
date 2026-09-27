# SPDX-License-Identifier: MIT
{ ... }:
{
  imports = [
    ./manifest.nix
    ./exports.nix
    ./lib.nix
    ./libOverlays.nix
    ./modules.nix
  ];
}
