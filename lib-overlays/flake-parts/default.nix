# SPDX-License-Identifier: MIT
#
# The flake-parts integration: projecting a composition into
# flake outputs. It owns the `flake` class and evaluates it with
# flake-parts' `evalFlakeModule`, as `mkFlake` does. Beside the entry
# points it carries the option types (option types are this
# integration's medium), the export machinery (the core flake-parts
# module reads the manifest of the evaluation, projects the
# `libOverlays` and `modules` flake outputs from it, and defaults
# flake-parts' `systems` from the `systems` the composition declared),
# and the `flake-parts` library mirror.
#
# flake-parts itself comes from the composition, resolved like every
# ecosystem (the explicit `ecosystemSrc`, `defaultEcosystemSrc.flake-parts`
# in the mkLib call, the pinned source named `flake-parts` in the
# `sources` passed to mkLib), and is taken as a source: its flake.nix is
# called with the
# composed library standing in for its `nixpkgs-lib` input, so the
# module evaluation runs on the same library everything else in the
# composition does, and on no library flake-parts assembled for itself.
{
  contributeClasses,
  mkLibOverlay,
  ...
}:

{

  imports = [
    # The library of nixpkgs, which this overlay calls through the
    # composed library, imported by key so it is composed wherever
    # this is.
    ((mkLibOverlay ../nixpkgs-lib) // { key = "nixpkgs-lib"; })
    # What an integration is written from, imported by key so it is
    # composed wherever this integration is.
    ((mkLibOverlay ../integrations) // { key = "integrations"; })
  ];

  overlay =
    final: prev:
    let

      resolveEcosystemSrc = final.caisson.integrations.resolveEcosystemSrc {
        name = "flake-parts";
        context = "caisson.flake-parts";
      };
      resolveSrc =
        explicit:
        resolveEcosystemSrc {
          inherit explicit;
          manifest = final.caisson-core.libManifest or { };
        };
      resolveOutPath = value: if builtins.isAttrs value && value ? outPath then value.outPath else value;

      # flake-parts instantiated over this composition: its flake.nix
      # applied to the composed library as `nixpkgs-lib`. What comes
      # out (`lib.evalFlakeModule`, `flakeModules`) is flake-parts'
      # machinery on caisson's library, with no second nixpkgs lib
      # inside it.
      flakePartsFor =
        explicit:
        final.caisson-core.callFlake {
          src = resolveOutPath (resolveSrc explicit);
          inputs.nixpkgs-lib = {
            lib = final;
          };
        };
      # The composition's declared flake-parts, instantiated per
      # composed library and shared by every evaluation that passes
      # no `ecosystemSrc`.
      flakePartsDefault = flakePartsFor null;

      # The option types of the core module, re-exported under this
      # namespace for the readers of that name.
      types = import ../../modules/generic/core/types.nix { lib = final; };

      # The evaluator's call, on the lib of the view being evaluated:
      # the manifest's sources as the flake's `inputs`, the special
      # arguments and the module location when the configuration is
      # named, beside the flake-parts it runs on and the module it
      # evaluates. `ecosystemArgs`, which only the twin's pattern
      # admits, is merged over the call last.
      evaluate =
        args:
        { lib, manifest }:
        let
          selection = lib.caisson.integrations;

          flakeParts =
            if (args.ecosystemSrc or null) == null then flakePartsDefault else flakePartsFor args.ecosystemSrc;

          # The flake class of the registry, the same source every
          # adapter selects from, so modules arriving by any channel
          # (local registration, overlay contribution, consumed
          # project) are selectable here.
          registry = lib.caisson-core.modules.flake or { };

          # The framework module of the class.
          frameworkModules = selection.frameworkModules "flake" registry;

          moduleImports = selection.moduleImportsOf "flake" { inherit lib manifest; } args;

          # The name this configuration holds: the attribute its parent
          # declares it under, or, at a top, the name the composition
          # declares on mkLib.
          name = manifest.name or null;

          # The configuration's module: the module passed, else the
          # configuration registered under the configuration's name
          # (`configs/flake/<name>`), else none.
          registered = lib.caisson-core.configs.flake or { };
          configModule =
            if (args.configModule or null) != null then
              args.configModule
            else if name != null then
              registered.${name} or null
            else
              null;

          # Exported modules are keyed by flake-parts' moduleLocation,
          # which defaults to self.outPath, a rev-sensitive identity, so
          # consumers composing this flake's modules from two different
          # revs (e.g. directly and via a sibling whose lock is one bump
          # behind) collect two copies of the same option declarations
          # and fail with "option ... is already declared". The
          # configuration's name is rev-independent, so such copies
          # deduplicate. It comes from the manifest rather than the
          # module evaluation because moduleLocation is consumed before
          # that evaluation exists.
          # flake-parts' `inputs` are the composition's pinned sources,
          # with `self` added below.
          callArgs =
            (if name != null then { moduleLocation = name; } else { })
            // {
              inputs = manifest.sources;
              specialArgs = {
                inherit lib;
              }
              // (if (args.pkgSets or null) != null then { inherit (args) pkgSets; } else { })
              // (if (args.specialArgs or null) != null then args.specialArgs else { });
            }
            // (if (args.ecosystemArgs or null) != null then args.ecosystemArgs else { });

          # The package set `perSystem` runs on, its `pkgs`: the
          # selection in force at the flake, applied to the package
          # sets available at each system. A package config that builds
          # no set for a system is not among the sets there, and a
          # flake with no package sets at a system keeps the `pkgs`
          # flake-parts provides. Every available set stays reachable
          # by name, as the `pkgSets` argument of perSystem.
          pkgSetModule = {
            _file = "caisson-flake-parts:pkgSet";
            perSystem =
              { system, lib, ... }:
              let
                available = builtins.mapAttrs (_: packageConfig: packageConfig.children.nixpkgs.${system}.value) (
                  lib.filterAttrs (_: packageConfig: packageConfig.children.nixpkgs ? ${system}) (
                    manifest.pkgSets or { }
                  )
                );
              in
              {
                _module.args.pkgs = lib.mkIf (available != { }) (
                  lib.mkDefault (
                    selection.pkgSetOf {
                      context = "lib.caisson.flake-parts.mkConfiguration";
                      what = "the flake at ${system}";
                    } manifest available
                  )
                );
              };
          };

          module = {
            imports = [
              flakeParts.flakeModules.flakeModules
              flakeParts.flakeModules.modules
            ]
            ++ frameworkModules
            ++ [ pkgSetModule ]
            ++ moduleImports registry
            ++ (if configModule == null then [ ] else [ configModule ]);
          };

          # flake-parts reads the flake's `self` from `inputs.self`, and
          # its modules take `self` and `self'` as arguments. The
          # integration ties that knot the way Nix does for a flake:
          # `self` is the evaluation's outputs with the root's source
          # info (out path, revision, last-modified) beside them, and
          # `self.inputs` the pinned sources. A composition with no root
          # names no tree, so its `self` has no out path. An `inputs`
          # handed in through the WithEcosystemArgs twin that carries a
          # `self` is taken as it is.
          given = callArgs.inputs or { };
          root = manifest.root or null;
          # The root's source-info fields that name something: a flake's
          # `self` carries only the fields its tree has, so a reader of
          # `self.rev or …` sees a dirty tree as Nix hands it over.
          sourceInfo = if root == null then { } else lib.filterAttrs (_: value: value != null) root;
          inputs = if given ? self then given else given // { inherit self; };
          self =
            outputs
            // sourceInfo
            // {
              _type = "flake";
              inherit inputs outputs sourceInfo;
              outPath =
                if root == null then
                  throw ''
                    caisson.flake-parts.mkConfiguration: `self.outPath` was read, but the
                    composition names no root. Pass `root` to caisson-core.mkLib
                    (`inherit (caisson-core.lib.caisson-core.pins.flake inputs) sources root;`
                    at a flake top).
                  ''
                else
                  root.outPath;
            };

          evaluated = flakeParts.lib.evalFlakeModule (callArgs // { inherit inputs; }) module;
          # What flake-parts' `mkFlake` returns from the evaluation.
          outputs = evaluated.config.processedFlake or evaluated.config.flake;
        in
        {
          value = evaluated;
          outputs = {
            flake = outputs;
          };
        };

      configuration =
        args:
        final.caisson.integrations.mkModuleConfiguration {
          type = "flake-parts";
          defaultPkgs = args.defaultPkgs or null;
          evaluate = evaluate args;
        };

      # What a flake returns from `outputs`, and what a flakeless top
      # that keeps flake-parts returns from `default.nix`: the flake
      # outputs of the configuration, finalized as a top is, under the
      # name the composition declares on mkLib.
      mkTopConfiguration =
        rawArgs:
        (final.caisson-core.finalizeTop (final.caisson.flake-parts.mkConfiguration rawArgs)).outputs.flake;

      integration = final.caisson.integrations.mkIntegration {
        name = "flake-parts";
        class = "flake";
        # What these return is a configuration, a function of
        # `{ name, parent }`: the parent that declares it under
        # `caisson.flake-parts.configurations.<name>` finalizes it, and
        # `mkTopConfiguration` finalizes it at a top. What the
        # evaluator takes beyond these arguments comes from the
        # manifest: the flake's `inputs` (`self` among them) and its
        # `moduleLocation`, the name of the configuration.
        mkConfiguration =
          {
            # The configuration's module. When absent, the configuration
            # registered under the configuration's name
            # (`lib.caisson-core.configs.flake.<name>`), if any. Further
            # modules of the class are selected with `moduleImports`,
            # from the registry.
            configModule ? null,
            # The package sets for the flake evaluation itself, handed
            # to the flake-class modules as the `pkgSets` special
            # argument. Per system package sets are built by the
            # nixpkgs integration from the package configs declared on
            # mkLib (`pkgSets`) and reach perSystem as `pkgSets`.
            pkgSets ? null,
            # The package set perSystem runs on, its `pkgs`: a function
            # that receives the package sets available at each system,
            # as an attribute set by package config name, and returns
            # the set to run on. The
            # selection holds for every configuration beneath the
            # flake that selects none. When absent, the selection of
            # the nearest configuration above, and the set named
            # `default` where none above selects.
            defaultPkgs ? null,
            # The flake-parts source; resolved from the composition's
            # declarations when absent.
            ecosystemSrc ? null,
            # The selection over the flake class of the registry. It
            # replaces the default of the class, which is every entry
            # named `default` followed by what the configurations
            # above added.
            moduleImports ? null,
            # A selection added to that selection, whichever it is.
            extraModuleImports ? null,
            # Extra module arguments, merged over those the framework
            # supplies.
            specialArgs ? null,
          }@args:
          configuration args;
        # The same arguments and `ecosystemArgs`, the evaluator's
        # arguments merged over the composed call last.
        mkConfigurationWithEcosystemArgs =
          {
            configModule ? null,
            pkgSets ? null,
            defaultPkgs ? null,
            ecosystemSrc ? null,
            moduleImports ? null,
            extraModuleImports ? null,
            specialArgs ? null,
            ecosystemArgs ? null,
          }@args:
          configuration args;
        extra = {
          inherit mkTopConfiguration types;
        };
      };

    in
    contributeClasses prev integration.classes
    // {

      caisson = (prev.caisson or { }) // {
        flake-parts = integration.namespace;
      };

      # The flake-parts library mirrored into the composed library,
      # from the composition's declared flake-parts; forced only when
      # read.
      flake-parts = (prev.flake-parts or { }) // flakePartsDefault.lib;

    };

}
