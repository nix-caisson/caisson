# SPDX-License-Identifier: MIT
#
# caisson's own composed library: the mkLib call with every
# registration this repository makes. Both tops evaluate it, flake.nix
# with caisson-core and the ecosystem sources resolved as flake inputs,
# default.nix with them fetched from the pins written there.
{
  # caisson-core's library (`lib.caisson-core` of its flake, or the
  # value of its default.nix).
  caisson-core,
  # The inputs the composition resolves its ecosystems from by name:
  # nixpkgs-lib and, for the flake top, flake-parts.
  inputs,
}:
caisson-core.mkLib {

  inherit inputs;

  # The platforms this tree builds on, declared once; the core
  # flake-parts module defaults flake-parts' `systems` from it.
  systems = [ "x86_64-linux" ];

  modules = composedLib: {
    flake = {
      default = composedLib.caisson.flake-parts.mkModule ../modules/flake-parts/default;
      # The nixpkgs integration's module layer: the overlay registry
      # (nixpkgs-interface) and the package-set machinery that reifies
      # `caisson.nixpkgs.pkgSets` per system (nixpkgs, which imports
      # the interface).
      nixpkgs = composedLib.caisson.flake-parts.mkModule ../modules/flake-parts/nixpkgs;
      nixpkgs-interface = composedLib.caisson.flake-parts.mkModule ../modules/flake-parts/nixpkgs-interface;
    };
  };

  libOverlays = mkLibOverlay: {
    structural = mkLibOverlay ../lib-overlays/structural;
    flake-parts = mkLibOverlay ../lib-overlays/flake-parts;
    tooling = mkLibOverlay ../lib-overlays/tooling;
    nixpkgs = mkLibOverlay ../lib-overlays/nixpkgs;
    nixos = mkLibOverlay ../lib-overlays/nixos;
    home-manager = mkLibOverlay ../lib-overlays/home-manager;
    colmena = mkLibOverlay ../lib-overlays/colmena;
    terranix = mkLibOverlay ../lib-overlays/terranix;
    system-manager = mkLibOverlay ../lib-overlays/system-manager;
  };

}
