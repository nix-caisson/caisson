# SPDX-License-Identifier: MIT
{ closure-lib, ... }:
{ lib, ... }:
{
  options.caisson.nixpkgs.overlays.all = lib.mkOption {
    description = ''
      The registry of known nixpkgs overlays, keyed by name. Each value is
      a function from this flake's `configName` to an overlay.

      Registering an overlay here does nothing by itself. The nixpkgs
      flake module's package sets select from this registry through
      `caisson.nixpkgs.pkgSets.<name>.overlayImports`, and the `overlays`
      flake output is selected from it through
      `caisson.nixpkgs.overlays.exported`; both selectors default to every
      registered overlay. A flake module that only wants to make an
      overlay available imports the `nixpkgs-interface` flake module and
      adds an entry here, leaving the consumer to select it.
    '';
    type = lib.types.lazyAttrsOf (
      lib.types.functionTo closure-lib.caisson.nixpkgs.types.nixpkgsOverlay
    );
    default = { };
  };
}
