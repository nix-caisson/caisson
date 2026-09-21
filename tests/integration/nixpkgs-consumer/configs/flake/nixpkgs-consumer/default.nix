# SPDX-License-Identifier: MIT
{ ... }:
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  mkIntegrationSample = { writeText }: writeText "integration-sample" "ok";
in
{
  systems = [ "x86_64-linux" ];

  caisson.configInfo.configName = "nixpkgs-consumer";

  caisson.nixpkgs = {
    config = {
      allowUnfree = true;
    };
    overlays = {
      all = {
        packages = lib.caisson.nixpkgs.mkPackagesOverlay (callPackage: {
          integration-sample = callPackage mkIntegrationSample { };
        });
        polyfill = lib.caisson.nixpkgs.mkPolyfillOverlay (
          _final: _prev: {
            polyfilledFlag = true;
          }
        );
      };
    };
    pkgSets = {
      pkgs = {
        pkgFunction = import inputs.nixpkgs;
        overlayImports = overlays: [
          overlays.packages
          overlays.polyfill
        ];
      };
      slim = {
        pkgFunction = import inputs.nixpkgs;
        overlayImports = overlays: [ overlays.packages ];
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
        assert (pkgSets.pkgs.config.allowUnfree or false);
        pkgs.runCommand "nixpkgs-consumer-success" { } "touch $out";
    };
}
