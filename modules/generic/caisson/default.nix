# SPDX-License-Identifier: MIT
#
# The options of caisson: the part of every framework module that is
# the same for every class. It declares the composition's manifest, the
# registry selectors (`caisson.libOverlays`, `caisson.pkgOverlays`,
# `caisson.modules.<class>`),
# `caisson.exports`, what the selectors chose, which a caisson top returns and
# a parent passes up, and, through the module of each integration of
# caisson, the configurations declared inside a configuration
# (`caisson.<integration>.configurations`). Registered under the
# class-free `generic` class
# (flake-parts' name for a module any class may import). The `core`
# module of every class imports this entry; those of `structural` and
# `flake` also add `perSystem`. What the modules declared here need
# comes through `lib`, the composed library in specialArgs.
#
# In a module evaluation whose library is not a caisson composition the
# module declares nothing: a module list that carries it can be handed
# to an evaluator that runs on a library of its making, as
# home-manager's NixOS module does for the home-manager configurations
# it embeds.
{ closure-lib, ... }:
{ lib, ... }:
{
  imports =
    if lib ? caisson && lib ? caisson-core then
      [
        ./manifest.nix
        ./checkCategories.nix
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
        (closure-lib.caisson.integrations.configurationsModuleFor [
          "caisson-colmena"
          "caisson-disko"
          "caisson-facter"
          "caisson-microvm"
          "caisson-nixops4-composite"
          "caisson-nixops4-resource"
          "colmena"
          "darwin"
          "disko"
          "facter"
          "flake-parts"
          "hjem"
          "home-manager"
          "kubenix"
          "microvm"
          "nemacs"
          "nix-unit"
          "nixidy"
          "nixops4"
          "nixos"
          "nixos-test"
          "nixpkgs"
          "nixvim"
          "nvf"
          "structural"
          "system-manager"
          "terranix"
          "topology"
          "treefmt"
        ])
      ]
    else
      [ ];
}
