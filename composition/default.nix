# SPDX-License-Identifier: MIT
#
# caisson's contributions to the caisson-core composition calculus
# (https://github.com/nix-caisson/caisson-core), exported as
# `lib.composition` on the flake.  This surface is additive: caisson's
# own mkLib still composes via the library-lifecycle machinery, and
# these entries let calculus consumers compose the same library ahead
# of that cutover.
{ inputs }:
{

  # ecosystemSrc: a directory importable as nixpkgs' lib, e.g.
  # "${nixpkgs}/lib" (full nixpkgs) or "${nixpkgs-lib}/lib" (the
  # github:nix-community/nixpkgs.lib mirror).
  entriesFor =
    { ecosystemSrc }:
    let
      coreOverlay =
        (import ../lib-overlays/core { inherit inputs; } { closure-inputs = inputs; }).overlay;
      defaultOverlay = (import ../lib-overlays/default { closure-inputs = inputs; }).overlay;
    in
    rec {

      base = {
        key = "caisson.nixpkgs-lib";
        imports = [ ];
        overlay = _final: _prev: import ecosystemSrc;
      };

      caisson-lib = {
        key = "caisson.lib";
        imports = [ base ];
        overlay =
          final: prev:
          let
            coreDelta = coreOverlay final prev;
            afterCore = prev // coreDelta;
          in
          coreDelta // defaultOverlay final afterCore;
      };

    };

}
