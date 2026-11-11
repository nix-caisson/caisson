# SPDX-License-Identifier: MIT
{ ... }:
{
  imports = [
    ./manifest.nix
    ./checkCategories.nix
    ./checks.nix
    ./checkStages.nix
    ./configurations.nix
    ./exportedChecks.nix
    ./exports.nix
    ./forChildren.nix
    ./forDirectChildren.nix
    ./forNearestChildren.nix
    ./libOverlays.nix
    ./modules.nix
    ./pkgOverlays.nix
  ];
}
