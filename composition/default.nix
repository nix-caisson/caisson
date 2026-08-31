# SPDX-License-Identifier: MIT
#
# caisson's contributions to caisson-core's keyed composition
# (https://github.com/nix-caisson/caisson-core), exported as
# `lib.composition` on the flake. These entries let consumers of
# caisson-core's `compose` build the same library that caisson's own
# mkLib builds: the
# machinery entry injects the `caisson-core` namespace, and each
# integration is an entry importing it.
{ inputs }:
{

  # ecosystemSrc: a directory importable as nixpkgs' lib, e.g.
  # "${nixpkgs}/lib" (full nixpkgs) or "${nixpkgs-lib}/lib" (the
  # github:nix-community/nixpkgs.lib mirror).
  entriesFor =
    { ecosystemSrc }:
    let
      caisson-core = import ../vendor/caisson-core/lib;
      baseLib = import ecosystemSrc;
      machineryOverlay = caisson-core.mkCoreOverlay {
        inherit inputs;
        defaultBaseLib = baseLib;
      };
    in
    let
      integrationEntry = target: {
        key = "caisson.${target}";
        imports = [ entries.caisson-lib ];
        overlay = (import (../lib-overlays + "/${target}") { closure-inputs = inputs; }).overlay;
      };

      entries = {

        base = {
          key = "caisson.nixpkgs-lib";
          imports = [ ];
          overlay = _final: _prev: baseLib;
        };

        caisson-lib = {
          key = "caisson.lib";
          imports = [ entries.base ];
          overlay = machineryOverlay.overlay;
        };

        flake-parts = integrationEntry "flake-parts";
        tooling = integrationEntry "tooling";
        nixpkgs = integrationEntry "nixpkgs";
        nixos = integrationEntry "nixos";
        home-manager = integrationEntry "home-manager";
        colmena = integrationEntry "colmena";
        terranix = integrationEntry "terranix";
        system-manager = integrationEntry "system-manager";

      };
    in
    entries;

}
