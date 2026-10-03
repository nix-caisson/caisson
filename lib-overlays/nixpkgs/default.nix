# SPDX-License-Identifier: MIT
#
# The nixpkgs integration: it owns the `nixpkgsConfig` class, the
# class nixpkgs evaluates `pkgs/top-level/config.nix` under,
# and builds package sets from package configs.
#
# A package config is declared in mkLib's `pkgSets` as a
# `lib.caisson.nixpkgs.mkConfiguration` call, which returns a function
# of `{ name, parent }`: mkLib calls it with the name it is declared
# under and its parent manifest. That call evaluates the config module over upstream's
# `config.nix`, with caisson's options under `caisson.nixpkgs`, and
# builds a package set per system in `caisson.nixpkgs.systems` as the
# config's children. caisson performs the instantiation itself rather
# than calling `pkgs/top-level/default.nix`, which would evaluate the
# config again and build the set on the lib it imports from its own
# tree: it resolves the systems, boots the stdenv stages and hands
# `stage.nix` the composed lib with `pkgsManifest` filled in, so
# `pkgs.lib` carries the set's manifest.
{
  closure-inputs,
  contributeClasses,
  entries,
  mkLibOverlay,
  ...
}:
{

  imports = [
    entries.nixpkgs-lib
    # What an integration is written from, imported by key so it is
    # composed wherever this integration is.
    ((mkLibOverlay ../integrations) // { key = "integrations"; })
  ];

  overlay = (
    final: prev:
    let
      prevNs = (prev.caisson or { }).nixpkgs or { };
      selection = final.caisson.integrations;

      resolveEcosystemSrc = selection.resolveEcosystemSrc {
        name = "nixpkgs";
        context = "lib.caisson.nixpkgs.mkConfiguration";
      };

      # The default package overlay selection: every entry named
      # `default`, the one this composition registers and those the
      # consumed projects contribute (`<project>/default`), as for
      # modules.
      defaultPkgOverlays =
        registry:
        builtins.attrValues (
          final.filterAttrs (name: _: name == "default" || final.hasSuffix "/default" name) registry
        );

      # The package set of nixpkgs at `src`, instantiated as
      # `pkgs/top-level/default.nix` instantiates it, from arguments
      # caisson has already resolved: `lib` is the composed lib the
      # stages and `stage.nix` run on, and `config` the evaluated
      # config. `nixpkgsFun`, which upstream's variants and
      # `appendOverlays` call to build a set with other arguments,
      # re-enters here; a call that passes a `config` has it evaluated
      # over `config.nix` the way upstream evaluates it, and every
      # other call keeps the evaluated config.
      instantiate =
        src: args:
        let
          inherit (args) lib config;
          overlays = args.overlays or [ ];
          crossOverlays = args.crossOverlays or [ ];
          localSystem = lib.systems.elaborate args.localSystem;
          # Condition preserves sharing, as upstream's does.
          crossSystem =
            let
              system = lib.systems.elaborate args.crossSystem;
            in
            if (args.crossSystem or null) == null || lib.systems.equals system localSystem then
              localSystem
            else
              system;
          nixpkgsFun =
            newArgs:
            instantiate src (
              args
              // newArgs
              // (if newArgs ? config then { config = evaluateConfig src lib newArgs.config; } else { })
            );
          allPackages =
            newArgs:
            import "${src}/pkgs/top-level/stage.nix" (
              {
                inherit lib nixpkgsFun;
              }
              // newArgs
            );
          boot = import "${src}/pkgs/stdenv/booter.nix" { inherit lib allPackages; };
          stdenvStages = args.stdenvStages or (import "${src}/pkgs/stdenv");
          stages = stdenvStages {
            inherit
              lib
              localSystem
              crossSystem
              config
              overlays
              crossOverlays
              ;
          };
          fixedPoint = boot stages;
          disallowed = config.attrPathsDisallowedForInternalUse or [ ];
          # Upstream removes these attribute paths from the set; only
          # CI sets them.
          removeAttrPaths =
            attrPaths: set:
            let
              split = lib.partition (attrPath: lib.length attrPath == 1) attrPaths;
              nested =
                set
                // lib.mapAttrs (name: paths: removeAttrPaths (map lib.tail paths) set.${name}) (
                  lib.groupBy lib.head split.wrong
                );
            in
            lib.removeAttrs nested (map lib.head split.right);
          pkgs =
            if disallowed == [ ] then
              fixedPoint
            else
              removeAttrPaths (map (x: x.attrPath) disallowed) fixedPoint;
          x86Darwin = system: system.isDarwin && system.isx86;
        in
        if !(builtins.isList overlays) then
          throw "The overlays of a nixpkgs package set must be a list."
        else if !(builtins.all builtins.isFunction overlays) then
          throw "Every overlay of a nixpkgs package set must be a function."
        else if !(builtins.isList crossOverlays) then
          throw "The crossOverlays of a nixpkgs package set must be a list."
        else if !(builtins.all builtins.isFunction crossOverlays) then
          throw "Every crossOverlay of a nixpkgs package set must be a function."
        else if
          (x86Darwin localSystem || x86Darwin crossSystem)
          && (config.allowDeprecatedx86_64Darwin or null) != "force"
        then
          throw "nixpkgs has dropped support for x86_64-darwin; set allowDeprecatedx86_64Darwin = \"force\" in the package config to override."
        else
          pkgs;

      # A nixpkgs config evaluated over `config.nix` of the tree at
      # `src`, with its assertions and warnings applied, the way
      # upstream evaluates the `config` argument.
      checkedConfig =
        lib: configEval: value:
        let
          failed = lib.filter (x: !x.assertion) configEval.config.assertions;
        in
        if failed != [ ] then
          throw "Failed assertions in the nixpkgs package config:\n${
            lib.concatMapStringsSep "\n" (x: "- ${x.message}") failed
          }"
        else
          lib.showWarnings configEval.config.warnings value;

      evaluateConfig =
        src: lib: config:
        let
          configEval = lib.evalModules {
            class = "nixpkgsConfig";
            # The composed lib, as every caisson evaluation hands it to
            # its modules; without it the module system passes the lib
            # upstream built `lib/modules.nix` with.
            specialArgs.lib = lib;
            modules = [
              "${src}/pkgs/top-level/config.nix"
              {
                _file = "nixpkgs.config";
                inherit config;
              }
            ];
          };
        in
        checkedConfig lib configEval configEval.config;

      # Caisson's options in the nixpkgs config class, under `caisson`
      # so that none shadows an upstream option, present or future.
      caissonConfigModule =
        { parent, pkgOverlayRegistry }:
        { lib, ... }:
        {
          _file = "lib.caisson.nixpkgs.mkConfiguration";
          options.caisson.nixpkgs = {
            systems = lib.mkOption {
              description = "The systems this package config builds a package set for, one child per system.";
              type = lib.types.listOf lib.types.str;
              default =
                if (parent.systems or null) == null then
                  throw ''
                    The nixpkgs package config builds a set per system in force where it is
                    declared, but none are declared. Declare `systems` in the mkLib call
                    (e.g. `systems = [ "x86_64-linux" ];`), or set `caisson.nixpkgs.systems`
                    in the config's module.
                  ''
                else
                  parent.systems;
              defaultText = lib.literalMD "the systems in force at the level the config is declared at";
            };
            overlays = lib.mkOption {
              description = "The package overlay registry entries this package config's sets apply, each after the entries it imports and each key once.";
              type = lib.types.listOf lib.types.raw;
              default = defaultPkgOverlays pkgOverlayRegistry;
              defaultText = lib.literalMD "every registry entry named `default` or `<project>/default`";
            };
          };
        };

      # Finalize a package config: evaluate it and build its sets. `lib`
      # is the lib the constructor was called through, the lib the
      # config is declared under.
      finalizeConfiguration =
        args:
        { name, parent }:
        let
          lib = final;
          src = toString (resolveEcosystemSrc {
            explicit = args.ecosystemSrc or null;
          });
          registry = lib.caisson-core.modules.nixpkgsConfig or { };
          pkgOverlayRegistry = parent.pkgOverlays or { };
          moduleImports =
            if (args.moduleImports or null) == null then selection.defaultModuleImports else args.moduleImports;
          # The config's module: the one passed, else the configuration
          # registered under the config's name
          # (`configs/nixpkgsConfig/<name>`), else none.
          configModule =
            if (args.configModule or null) != null then
              args.configModule
            else
              (lib.caisson-core.configs.nixpkgsConfig or { }).${name} or null;
          configEval = lib.evalModules {
            class = "nixpkgsConfig";
            # The composed lib, so a config module reads
            # `lib.caisson.nixpkgs.overlays` and the rest of the lib the
            # config is declared under.
            specialArgs.lib = lib;
            modules = [
              "${src}/pkgs/top-level/config.nix"
              (caissonConfigModule { inherit parent pkgOverlayRegistry; })
            ]
            ++ selection.coreModules registry
            ++ moduleImports registry
            ++ (if configModule == null then [ ] else [ configModule ]);
          };
          caissonConfig = configEval.config.caisson.nixpkgs;
          # The config handed to nixpkgs: the evaluated config without
          # caisson's options.
          config = checkedConfig lib configEval (builtins.removeAttrs configEval.config [ "caisson" ]);
          # The project's scope, `pkgs.<project>`, present in every
          # set even when nothing contributes to it.
          projectName = parent.name or null;
          scopeOverlay = final': prev': { ${projectName} = prev'.${projectName} or { }; };
          overlays =
            (if projectName == null then [ ] else [ scopeOverlay ])
            ++ lib.caisson-core.pkgOverlaysFor caissonConfig.overlays;
          ecosystemArgs = args.ecosystemArgs or { };

          setFor =
            system:
            let
              setManifest = {
                _type = "caisson-manifest";
                type = "nixpkgs";
                name = system;
                parent = manifest;
                ancestors = manifest.ancestors ++ [ manifest ];
                nearest = manifest.nearest // {
                  nixpkgs = manifest;
                };
                inputs = [ ];
                childless = false;
                children = { };
                inherit system;
                entries = builtins.map (entry: entry.key) caissonConfig.overlays;
                value = pkgs;
              };
              pkgs = instantiate src (
                {
                  lib = lib.caisson-core.withManifests { pkgsManifest = setManifest; };
                  localSystem = { inherit system; };
                  inherit config overlays;
                }
                // ecosystemArgs
              );
            in
            setManifest;

          manifest = {
            _type = "caisson-manifest";
            type = "nixpkgs";
            inherit name parent;
            ancestors = (parent.ancestors or [ ]) ++ [ parent ];
            nearest = parent.nearest or { };
            inputs = [ ];
            # A package config declares no configurations beneath it
            # (its sets are built, not declared), so its
            # childless and full manifests coincide.
            childless = false;
            inherit (caissonConfig) systems;
            ecosystemSrc = src;
            pkgOverlays = builtins.map (entry: entry.key) caissonConfig.overlays;
            value = configEval;
            inherit config;
            children.nixpkgs = final.genAttrs caissonConfig.systems setFor;
          };
        in
        manifest;

      integration = selection.mkIntegration {
        name = "nixpkgs";
        class = "nixpkgsConfig";
        mkConfiguration =
          {
            # The package config's module, of class nixpkgsConfig:
            # nixpkgs' options at the top level, caisson's under
            # `caisson.nixpkgs`. When absent, the configuration
            # registered under the config's name
            # (`lib.caisson-core.configs.nixpkgsConfig.<name>`), if any.
            # Further modules of the class are selected with
            # `moduleImports`, from the registry.
            configModule ? null,
            # The selection over the nixpkgsConfig class of the
            # registry; every entry named `default` when absent.
            moduleImports ? null,
            # The nixpkgs source tree; resolved from the composition's
            # declarations when absent.
            ecosystemSrc ? null,
          }@args:
          finalizeConfiguration args;
        # The same arguments and `ecosystemArgs`, the instantiation's
        # arguments (`crossSystem`, `crossOverlays`, `stdenvStages`)
        # merged over the composed ones last, for every set.
        mkConfigurationWithEcosystemArgs =
          {
            configModule ? null,
            moduleImports ? null,
            ecosystemSrc ? null,
            ecosystemArgs ? null,
          }@args:
          finalizeConfiguration args;
        extra = {

          # The package configs declared at this lib, by config name:
          # each config's manifest, with a set per system under
          # `children.nixpkgs.<system>`. Empty until the full lib, where
          # mkLib has recorded them.
          pkgSets = final.caisson-core.libManifest.pkgSets or { };

          # The package overlay registry visible here, by registry
          # name, for a package config module's overlay selection
          # (`caisson.nixpkgs.overlays = [ lib.caisson.nixpkgs.overlays.<name> ];`).
          overlays = final.caisson-core.libManifest.pkgOverlays or { };

          mkScope = (
            pkgs: scopeFunction: final.makeScope pkgs.newScope (scope: scopeFunction scope.callPackage)
          );

          mkPackagesOverlay = (
            pkgs:
            let
              finalLib = final;
              closedInputs = closure-inputs;
              reifiedPkgs = if builtins.isFunction pkgs then pkgs else import pkgs;
              reifiedPkgsArgs =
                if builtins.isFunction reifiedPkgs then builtins.functionArgs reifiedPkgs else { };
              pkgsExpectsContext = reifiedPkgsArgs != { };
            in
            (name: pkgsFinal: pkgsPrev: {
              "${name}" =
                (pkgsPrev."${name}" or { })
                // (finalLib.caisson.nixpkgs.mkScope pkgsFinal (
                  callPackage:
                  if pkgsExpectsContext then
                    reifiedPkgs {
                      inherit callPackage;
                      inputs = closedInputs;
                      lib = finalLib;
                    }
                  else
                    reifiedPkgs callPackage
                ));
            })
          );

          mkPolyfillOverlay = (
            overlayFn:
            let
              finalLib = final;
              closedInputs = closure-inputs;
              reifiedOverlayFn = if builtins.isFunction overlayFn then overlayFn else import overlayFn;
              reifiedOverlayFnArgs =
                if builtins.isFunction reifiedOverlayFn then builtins.functionArgs reifiedOverlayFn else { };
              overlayExpectsContext = reifiedOverlayFnArgs != { };
              resolvedOverlayFn =
                if overlayExpectsContext then
                  reifiedOverlayFn {
                    inputs = closedInputs;
                    lib = finalLib;
                  }
                else
                  reifiedOverlayFn;
            in
            _name: pkgsFinal: pkgsPrev:
            resolvedOverlayFn pkgsFinal pkgsPrev
          );

          types = (prevNs.types or { }) // {

            nixpkgsOverlay = final.mkOptionType {
              name = "nixpkgs-overlay";
              description = "nixpkgs overlay";
              check = final.isFunction;
              merge = final.mergeOneOption;
            };

            nixpkgs = final.mkOptionType {
              name = "nixpkgs";
              description = "An evaluation of Nixpkgs; the top level attribute set of packages";
              check = builtins.isAttrs;
            };

          };

        };
      };
    in
    contributeClasses prev integration.classes
    // {
      caisson = (prev.caisson or { }) // {
        nixpkgs = prevNs // integration.namespace;
      };
    }
  );

}
