# SPDX-License-Identifier: MIT
#
# The `libOverlays` registration of caisson itself, shared by both
# tops: the integrations and the tooling, as the function mkLib takes.
mkLibOverlay: {
  structural = mkLibOverlay ./lib-overlays/structural;
  flake-parts = mkLibOverlay ./lib-overlays/flake-parts;
  tooling = mkLibOverlay ./lib-overlays/tooling;
  nixpkgs = mkLibOverlay ./lib-overlays/nixpkgs;
  nixos = mkLibOverlay ./lib-overlays/nixos;
  home-manager = mkLibOverlay ./lib-overlays/home-manager;
  colmena = mkLibOverlay ./lib-overlays/colmena;
  terranix = mkLibOverlay ./lib-overlays/terranix;
  system-manager = mkLibOverlay ./lib-overlays/system-manager;
}
