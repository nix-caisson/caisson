# SPDX-License-Identifier: MIT
#
# A typical consumer of the nixpkgs flake module: its package overlays
# are registry entries (pkg-overlays/, registered on mkLib), the `pkgs`
# set applies the default selection plus the polyfill entry, and the
# `slim` set applies the default selection alone.
{ ... }:
{
  inputs,
  ...
}:
{
  systems = [ "x86_64-linux" ];

  caisson.nixpkgs = {
    config = {
      allowUnfree = true;
    };
    pkgSets = {
      pkgs = {
        pkgFunction = import inputs.nixpkgs;
        pkgOverlayImports = registry: [
          registry.default
          registry.polyfill
        ];
      };
      slim = {
        pkgFunction = import inputs.nixpkgs;
      };
    };
    pkgs.export.enabled = true;
  };

  perSystem =
    {
      config,
      pkgSets,
      pkgs,
      ...
    }:
    {
      checks.nixpkgs-consumer-success =
        assert pkgs ? "nixpkgs-consumer";
        assert pkgs."nixpkgs-consumer" ? integration-sample;
        assert config.packages ? integration-sample;
        assert config.legacyPackages ? polyfilledFlag;
        assert pkgSets.pkgs ? polyfilledFlag;
        assert !(pkgSets.slim ? polyfilledFlag);
        assert pkgSets.slim."nixpkgs-consumer" ? integration-sample;
        assert (pkgSets.pkgs.config.allowUnfree or false);
        pkgs.runCommand "nixpkgs-consumer-success" { } "touch $out";
    };
}
