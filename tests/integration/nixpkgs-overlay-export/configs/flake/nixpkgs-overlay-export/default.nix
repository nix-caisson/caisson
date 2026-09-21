# SPDX-License-Identifier: MIT
{ ... }:
{
  inputs,
  lib,
  self,
  ...
}:
{
  # The registry (via the default moduleImports over the projects
  # channel) already applies the nixpkgs flake module; importing the
  # projected copy from the flake output as well must deduplicate.
  imports = [ inputs.parent.flakeModules.nixpkgs ];

  systems = [ "x86_64-linux" ];

  caisson.configInfo.configName = "nixpkgs-overlay-export";

  caisson.nixpkgs = {
    overlays = {
      all = {
        polyfillOnly = lib.caisson.nixpkgs.mkPolyfillOverlay (
          _final: _prev: {
            exportedPolyfill = "ok";
          }
        );
        internalOnly = lib.caisson.nixpkgs.mkPolyfillOverlay (
          _final: _prev: {
            internalOnly = true;
          }
        );
      };
      exported = overlays: {
        inherit (overlays) polyfillOnly;
      };
      export.enabled = true;
    };
    pkgSets = {
      pkgs = {
        pkgFunction = import inputs.nixpkgs;
      };
    };
  };

  perSystem =
    { pkgs, system, ... }:
    {
      checks.nixpkgs-overlay-export-success =
        let
          exportedNames = builtins.attrNames self.overlays;
          first = self.overlays.polyfillOnly { } { };
          second = self.overlays.polyfillOnly { } { };
          downstreamOverlay = self.overlays.polyfillOnly;
          downstreamPkgs = import inputs.nixpkgs {
            inherit system;
            overlays = [ downstreamOverlay ];
          };
        in
        assert exportedNames == [ "polyfillOnly" ];
        assert !(self.overlays ? internalOnly);
        assert first == second;
        assert downstreamPkgs.exportedPolyfill == "ok";
        pkgs.runCommand "nixpkgs-overlay-export-success" { } "touch $out";
    };
}
