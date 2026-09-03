# SPDX-License-Identifier: MIT
{ closure-lib, ... }:
{ config, lib, ... }:
let
  configName = config.caisson.configInfo.configName;
  coreOverlay = (final: prev: { "${configName}" = prev."${configName}" or { }; });
  cfg = config.caisson.nixpkgs.config;
  reifyPkgSet =
    system: overlays: name: pkgSet:
    (pkgSet.pkgFunction {
      inherit system;
      config = cfg;
      overlays = [ coreOverlay ] ++ (pkgSet.overlayImports overlays);
    });
  reifyPkgSets =
    system: overlays: builtins.mapAttrs (reifyPkgSet system overlays) config.caisson.nixpkgs.pkgSets;
in
{

  options.caisson.nixpkgs = {

    # `overlays.all` (the registry) is declared by the nixpkgs-interface
    # module.
    overlays = {
      export.enabled = lib.mkEnableOption "package overlay export";
      exported = lib.mkOption {
        description = "A function from the set of all known package overlays to a set of overlays to export from this flake.";
        type = lib.types.functionTo (
          lib.types.lazyAttrsOf closure-lib.caisson.nixpkgs.types.nixpkgsOverlay
        );
      };
    };

    config = lib.mkOption {
      description = "The package config to apply to generated package sets";
      type = lib.types.raw;
      default = { };
    };

    pkgs = {
      export.enabled = lib.mkEnableOption "legacyPackages export";
    };

    packages = {
      export.enabled = lib.mkOption {
        description = "Whether to export this flake's own package scope (pkgs.<configName>) as the packages output. Defaults to following pkgs.export.enabled.";
        type = lib.types.bool;
        default = config.caisson.nixpkgs.pkgs.export.enabled;
        defaultText = lib.literalExpression "config.caisson.nixpkgs.pkgs.export.enabled";
      };
    };

    pkgSets = lib.mkOption {
      description = "A dictionary of package set definitions to reify for each target system.";
      type = lib.types.attrsOf (
        lib.types.submoduleWith {
          modules = [
            ({
              options = {
                pkgFunction = lib.mkOption {
                  description = "The base package set to which the configured config and overlays will be applied. Should be a function that takes standard nixpkgs arguments (at least config, overlays, and localSystem).";
                  type = lib.types.raw;
                };
                overlayImports = lib.mkOption {
                  description = "A function from the attrSet of known package overlays to the ones to apply to this package set.";
                  type = lib.types.functionTo (lib.types.listOf closure-lib.caisson.nixpkgs.types.nixpkgsOverlay);
                  default = builtins.attrValues;
                };
              };
            })
          ];
        }
      );
    };
  };

  config = (
    let
      allOverlays = builtins.mapAttrs (
        name: overlayFunc: overlayFunc config.caisson.configInfo.configName
      ) config.caisson.nixpkgs.overlays.all;
    in
    {
      flake.overlays = lib.mkIf config.caisson.nixpkgs.overlays.export.enabled (
        let
          exportedOverlays = config.caisson.nixpkgs.overlays.exported allOverlays;
        in
        exportedOverlays
      );
      caisson.nixpkgs = {
        pkgSets = lib.mkDefault { };
        overlays = {
          exported = lib.mkDefault (overlays: overlays);
        };
      };
      perSystem =
        { pkgs, system, ... }:
        {
          _module.args = (
            let
              pkgSets = reifyPkgSets system allOverlays;
            in
            {
              pkgSets = pkgSets;
              pkgs = lib.mkDefault pkgSets.pkgs;
            }
          );
          legacyPackages = lib.mkIf config.caisson.nixpkgs.pkgs.export.enabled pkgs;
          packages = lib.mkIf config.caisson.nixpkgs.packages.export.enabled (
            builtins.removeAttrs pkgs."${configName}" [
              "callPackage"
              "newScope"
              "overrideScope"
              "packages"
            ]
          );
        };
    }
  );

}
