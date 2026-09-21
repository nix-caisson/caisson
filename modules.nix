# SPDX-License-Identifier: MIT
#
# The `modules` registration of caisson itself, shared by both tops:
# the flake modules this repository registers, as the function mkLib
# takes.
lib: {
  flake = {
    default = lib.caisson.flake-parts.mkModule ./modules/flake-parts/default;
    # The nixpkgs integration's module layer: the overlay registry
    # (nixpkgs-interface) and the package-set machinery that reifies
    # `caisson.nixpkgs.pkgSets` per system (nixpkgs, which imports
    # the interface).
    nixpkgs = lib.caisson.flake-parts.mkModule ./modules/flake-parts/nixpkgs;
    nixpkgs-interface = lib.caisson.flake-parts.mkModule ./modules/flake-parts/nixpkgs-interface;
  };
}
