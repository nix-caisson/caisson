# SPDX-License-Identifier: MIT
{ ... }:
{
  config,
  lib,
  ...
}:
let
  # The project's name, declared as `name` on mkLib and taken from the
  # manifest the composed library carries (`lib` is that library). It
  # names the flake's package scope (`pkgs.<name>`) that the packages
  # export publishes. A composition that declares none has no such
  # scope, and the message says so where the name is first needed.
  declaredName = lib.caisson-core.libManifest.name or null;
  namespace =
    assert lib.assertMsg (declaredName != null)
      "The nixpkgs flake module names this flake's package scope `pkgs.<name>` after the project's name, but this composition declares no name. Declare `name` in the mkLib call.";
    declaredName;

  # The package overlay registry mkLib holds, and the function that
  # turns a selection of its entries into the overlays to apply.
  inherit (lib.caisson-core) pkgOverlaysFor;

  # The registry entries the export selector chose, as plain nixpkgs
  # overlays under their names, each with the entries it imports
  # composed in, so a consumer that is not caisson gets a working
  # overlay.
  exportedRegistryOverlays = builtins.mapAttrs (
    _: entry: lib.composeManyExtensions (pkgOverlaysFor [ entry ])
  ) config.caisson.exports.pkgOverlays;

  # The package configs declared in mkLib's `pkgSets`, each with a set
  # per system among its children; a config without a set for a
  # system has none there. A composition that does not select the
  # nixpkgs integration has no package configs.
  packageConfigs = (lib.caisson.nixpkgs or { }).pkgSets or { };
  pkgSetsAt =
    system:
    builtins.mapAttrs (_: packageConfig: packageConfig.children.nixpkgs.${system}.value) (
      lib.filterAttrs (_: packageConfig: packageConfig.children.nixpkgs ? ${system}) packageConfigs
    );
in
{

  options.caisson.nixpkgs = {

    pkgs = {
      export.enabled = lib.mkEnableOption "legacyPackages export";
    };

    packages = {
      export.enabled = lib.mkOption {
        description = "Whether to export this flake's package scope (pkgs.<namespace>, the namespace the composition declares) as the packages output. Defaults to following pkgs.export.enabled.";
        type = lib.types.bool;
        default = config.caisson.nixpkgs.pkgs.export.enabled;
        defaultText = lib.literalExpression "config.caisson.nixpkgs.pkgs.export.enabled";
      };
    };
  };

  config = {
    # The `overlays` output: the package overlay registry's exported
    # entries as plain overlays.
    flake.overlays = lib.mkIf (exportedRegistryOverlays != { }) exportedRegistryOverlays;
    perSystem =
      { pkgs, system, ... }:
      {
        _module.args =
          let
            pkgSets = pkgSetsAt system;
          in
          {
            # Every package config's set at this system, by config
            # name, the only place a bare `pkgSets` module argument is
            # set.
            inherit pkgSets;
          };
        legacyPackages = lib.mkIf config.caisson.nixpkgs.pkgs.export.enabled pkgs;
        packages = lib.mkIf config.caisson.nixpkgs.packages.export.enabled (
          builtins.removeAttrs pkgs."${namespace}" [
            "callPackage"
            "newScope"
            "overrideScope"
            "packages"
          ]
        );
      };
  };

}
