# SPDX-License-Identifier: MIT
{ closure-lib, ... }:
{
  inputs,
  self,
  ...
}:
{
  # The default moduleImports already apply the nixpkgs flake module
  # of caisson, from the registry. Importing the same registry entry
  # here as well must deduplicate.
  imports = [ closure-lib.caisson-core.modules.flake."caisson/nixpkgs" ];

  systems = [ "x86_64-linux" ];

  # The export selector publishes one of the two local registry entries.
  caisson.pkgOverlays.exported = registry: {
    inherit (registry) polyfillOnly;
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
        assert
          builtins.attrNames self.lib.caisson-core.evalManifest.outputs.exports.pkgOverlays == [
            "polyfillOnly"
          ];
        assert first == second;
        assert downstreamPkgs.exportedPolyfill == "ok";
        pkgs.runCommand "nixpkgs-overlay-export-success" { } "touch $out";
    };
}
