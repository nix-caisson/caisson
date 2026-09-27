# SPDX-License-Identifier: MIT
{ closure-lib, ... }:
{
  config,
  options,
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

  # A package set applies the registry's selected overlays before the
  # overlays of `caisson.nixpkgs.overlays.all`. The registry holds the
  # declared package overlay layers, a consumed project's among them;
  # `overlays.all` is the config-side registry this move retires, and a
  # flake's own entries there come after, so they can still adjust what
  # a project's entry provides until they move to the registry.
  reifyPkgSet =
    system: overlays: name: pkgSet:
    (pkgSet.pkgFunction {
      inherit system;
      config = cfg;
      overlays = [
        coreOverlay
      ]
      ++ pkgOverlaysFor (pkgSet.pkgOverlayImports pkgOverlayRegistry)
      ++ (pkgSet.overlayImports overlays);
    });

  # The names of `overlays.all` this flake defines itself: those a
  # definition from a file in the flake's tree (its root) sets. An entry
  # a consumed project's module pushed into the registry is defined in
  # that project's files, so it is not local. With no root to compare
  # against, every entry counts as local.
  rootPrefix =
    let
      root = lib.caisson-core.libManifest.root or null;
    in
    if root == null then null else toString root.outPath + "/";
  namesDefinedBy =
    value:
    let
      type = value._type or null;
    in
    if type == "if" then
      (if value.condition then namesDefinedBy value.content else [ ])
    else if type == "merge" then
      builtins.concatMap namesDefinedBy value.contents
    else if type == "override" || type == "order" then
      namesDefinedBy value.content
    else if builtins.isAttrs value then
      builtins.attrNames value
    else
      [ ];
  localOverlayNames = builtins.concatMap (def: namesDefinedBy def.value) (
    builtins.filter (def: lib.hasPrefix rootPrefix (toString def.file)) (
      options.caisson.nixpkgs.overlays.all.definitionsWithLocations or [ ]
    )
  );
  localOverlays =
    overlays:
    if rootPrefix == null then
      overlays
    else
      lib.filterAttrs (name: _: builtins.elem name localOverlayNames) overlays;

  # The registry entries the export selector chose, as plain nixpkgs
  # overlays under their names, each with the entries it imports
  # composed in, so a consumer that is not caisson gets a working
  # overlay.
  exportedRegistryOverlays = builtins.mapAttrs (
    _: entry: lib.composeManyExtensions (pkgOverlaysFor [ entry ])
  ) config.caisson.exports.pkgOverlays;
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
        description = "A function from the set of all known package overlays to a set of overlays to export from this flake. Defaults to the overlays this flake defines itself (in files of its own tree); an entry a consumed project's module pushed into the registry leaves only when a selector names it.";
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
                overlayImports = lib.mkOption {
                  description = "A function from the attrSet of known package overlays to the ones to apply to this package set.";
                  type = lib.types.functionTo (lib.types.listOf closure-lib.caisson.nixpkgs.types.nixpkgsOverlay);
                  default = builtins.attrValues;
                };
                pkgOverlayImports = lib.mkOption {
                  description = "A function from the package overlay registry (mkLib's `pkgOverlays`, consumed projects' entries under `<project>/<name>`) to the list of entries this package set applies, before `overlayImports`. Each entry is applied after the entries it imports, and each key once.";
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

  config = (
    let
      allOverlays = builtins.mapAttrs (
        name: overlayFunc: overlayFunc namespace
      ) config.caisson.nixpkgs.overlays.all;
    in
    {
      # The `overlays` output: what `overlays.exported` chose from
      # `overlays.all` when that export is enabled, and the package
      # overlay registry's exported entries as plain overlays. A name
      # both define is an error, as for any two definitions of one
      # output attribute.
      flake.overlays =
        lib.mkIf (config.caisson.nixpkgs.overlays.export.enabled || exportedRegistryOverlays != { })
          (
            lib.mkMerge [
              (lib.mkIf config.caisson.nixpkgs.overlays.export.enabled (
                config.caisson.nixpkgs.overlays.exported allOverlays
              ))
              exportedRegistryOverlays
            ]
          );
      caisson.nixpkgs = {
        pkgSets = lib.mkDefault { };
        overlays = {
          exported = lib.mkDefault localOverlays;
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
    }
  );

}
