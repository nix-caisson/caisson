# SPDX-License-Identifier: MIT
{ ... }:
{
  config,
  lib,
  ...
}:
let
  # The namespace this composition declares on mkLib, taken from the
  # manifest the composed library carries (`lib` is that library). It
  # names the flake's package scope (`pkgs.<namespace>`) and keys the
  # overlays built over it. A composition that declares none has no
  # such scope, and the message says so where the name is first needed.
  declaredNamespace = lib.caisson-core.libManifest.namespace or null;
  namespace =
    assert lib.assertMsg (declaredNamespace != null)
      "The nixpkgs flake module names this flake's package scope `pkgs.<namespace>`, but this composition declares no namespace. Declare `namespace` in the mkLib call.";
    declaredNamespace;
  coreOverlay = (final: prev: { "${namespace}" = prev."${namespace}" or { }; });
  cfg = config.caisson.nixpkgs.config;

  # The package overlay registry mkLib holds (`pkgOverlays`, consumed
  # projects' entries under `<project>/<name>`), and the function that
  # turns a selection of its entries into the overlays to apply, each
  # entry after the entries it imports and each key once.
  pkgOverlayRegistry = lib.caisson-core.libManifest.pkgOverlays or { };
  inherit (lib.caisson-core) pkgOverlaysFor;

  # The default selection from the registry: every entry named
  # `default`, this composition's and each consumed project's
  # (`<project>/default`), as for modules.
  defaultPkgOverlays =
    registry:
    builtins.attrValues (
      lib.filterAttrs (name: _: name == "default" || lib.hasSuffix "/default" name) registry
    );

  # A package set applies the package overlay registry's selected
  # entries, the only package overlay route.
  reifyPkgSet =
    system: name: pkgSet:
    (pkgSet.pkgFunction {
      inherit system;
      config = cfg;
      overlays = [
        coreOverlay
      ]
      ++ pkgOverlaysFor (pkgSet.pkgOverlayImports pkgOverlayRegistry);
    });

  # The registry entries the export selector chose, as plain nixpkgs
  # overlays under their names, each with the entries it imports
  # composed in, so a consumer that is not caisson gets a working
  # overlay.
  exportedRegistryOverlays = builtins.mapAttrs (
    _: entry: lib.composeManyExtensions (pkgOverlaysFor [ entry ])
  ) config.caisson.exports.pkgOverlays;
  reifyPkgSets = system: builtins.mapAttrs (reifyPkgSet system) config.caisson.nixpkgs.pkgSets;
in
{

  options.caisson.nixpkgs = {

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
        description = "Whether to export this flake's package scope (pkgs.<namespace>, the namespace the composition declares) as the packages output. Defaults to following pkgs.export.enabled.";
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
                pkgOverlayImports = lib.mkOption {
                  description = "A function from the package overlay registry (mkLib's `pkgOverlays`, consumed projects' entries under `<project>/<name>`) to the list of entries this package set applies. Each entry is applied after the entries it imports, and each key once.";
                  type = lib.types.functionTo (lib.types.listOf lib.types.raw);
                  default = defaultPkgOverlays;
                  defaultText = lib.literalMD "every entry named `default` or `<project>/default`";
                };
              };
            })
          ];
        }
      );
    };
  };

  config = ({
    # The `overlays` output: the package overlay registry's exported
    # entries as plain overlays.
    flake.overlays = lib.mkIf (exportedRegistryOverlays != { }) exportedRegistryOverlays;
    caisson.nixpkgs.pkgSets = lib.mkDefault { };
    perSystem =
      { pkgs, system, ... }:
      {
        _module.args = (
          let
            pkgSets = reifyPkgSets system;
          in
          {
            pkgSets = pkgSets;
            # Claim the default `pkgs` only when a `pkgs` package set
            # is configured: the module reaches every composition that
            # selects the full registry, and a flake with no package
            # sets keeps flake-parts' own `pkgs` default.
            pkgs = lib.mkIf (config.caisson.nixpkgs.pkgSets ? pkgs) (lib.mkDefault pkgSets.pkgs);
          }
        );
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
  });

}
