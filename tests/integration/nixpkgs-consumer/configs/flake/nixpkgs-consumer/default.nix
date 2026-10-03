# SPDX-License-Identifier: MIT
#
# A typical consumer of the nixpkgs flake module: its package overlays
# are registry entries (pkg-overlays/, registered on mkLib), and its
# package configs are declared on mkLib (`default` and `slim`); the
# flake reads their sets as `pkgSets`, with `default` as `pkgs`.
{ ... }:
{ ... }:
{
  systems = [ "x86_64-linux" ];

  caisson.nixpkgs.pkgs.export.enabled = true;

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
        assert pkgSets.default ? polyfilledFlag;
        assert !(pkgSets.slim ? polyfilledFlag);
        assert pkgSets.slim."nixpkgs-consumer" ? integration-sample;
        assert (pkgSets.default.config.allowUnfree or false);
        pkgs.runCommand "nixpkgs-consumer-success" { } "touch $out";
    };
}
