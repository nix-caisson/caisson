# SPDX-License-Identifier: MIT
{ closure-inputs, ... }:
{

  imports = [ ];

  overlay = (
    final: prev: {
      caisson-nixpkgs = (prev.caisson-nixpkgs or { }) // {

        mkScope = (
          pkgs: scopeFunction: final.makeScope pkgs.newScope (scope: scopeFunction scope.callPackage)
        );

        mkPackagesOverlay = (
          pkgs:
          let
            finalLib = final;
            closedInputs = closure-inputs;
            reifiedPkgs = if builtins.isFunction pkgs then pkgs else import pkgs;
            reifiedPkgsArgs =
              if builtins.isFunction reifiedPkgs then builtins.functionArgs reifiedPkgs else { };
            pkgsExpectsContext = reifiedPkgsArgs != { };
          in
          (name: pkgsFinal: pkgsPrev: {
            "${name}" =
              (pkgsPrev."${name}" or { })
              // (finalLib.caisson-nixpkgs.mkScope pkgsFinal (
                callPackage:
                if pkgsExpectsContext then
                  reifiedPkgs {
                    inherit callPackage;
                    inputs = closedInputs;
                    lib = finalLib;
                  }
                else
                  reifiedPkgs callPackage
              ));
          })
        );

        mkPolyfillOverlay = (
          overlayFn:
          let
            finalLib = final;
            closedInputs = closure-inputs;
            reifiedOverlayFn = if builtins.isFunction overlayFn then overlayFn else import overlayFn;
            reifiedOverlayFnArgs =
              if builtins.isFunction reifiedOverlayFn then builtins.functionArgs reifiedOverlayFn else { };
            overlayExpectsContext = reifiedOverlayFnArgs != { };
            resolvedOverlayFn =
              if overlayExpectsContext then
                reifiedOverlayFn {
                  inputs = closedInputs;
                  lib = finalLib;
                }
              else
                reifiedOverlayFn;
          in
          _name: pkgsFinal: pkgsPrev:
          resolvedOverlayFn pkgsFinal pkgsPrev
        );

        types = ((prev.caisson-nixpkgs or { }).types or { }) // {

          nixpkgsOverlay = final.mkOptionType {
            name = "nixpkgs-overlay";
            description = "nixpkgs overlay";
            check = final.isFunction;
            merge = final.mergeOneOption;
          };

          nixpkgs = final.mkOptionType {
            name = "nixpkgs";
            description = "An evaluation of Nixpkgs; the top level attribute set of packages";
            check = builtins.isAttrs;
          };

        };

      };
    }
  );

}
