# SPDX-License-Identifier: MIT
#
# The `modules` registration of caisson itself, shared by both tops:
# the flake modules this repository registers, as the function mkLib
# takes.
composedLib: {
  flake = {
    default = composedLib.caisson.flake-parts.mkModule ./modules/flake-parts/default;
    # The nixpkgs integration's module layer: the overlay registry
    # (nixpkgs-interface) and the package-set machinery that reifies
    # `caisson.nixpkgs.pkgSets` per system (nixpkgs, which imports
    # the interface).
    nixpkgs = composedLib.caisson.flake-parts.mkModule ./modules/flake-parts/nixpkgs;
    nixpkgs-interface = composedLib.caisson.flake-parts.mkModule ./modules/flake-parts/nixpkgs-interface;
  };
}
