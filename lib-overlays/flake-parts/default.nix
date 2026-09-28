# SPDX-License-Identifier: MIT
#
# The flake-parts integration: projecting a composition into
# flake outputs. It owns the `flake` class and evaluates it with
# flake-parts' `mkFlake`. Beside the entry points it carries the option
# types (option types are this integration's medium), the export
# machinery (the core flake-parts module reads the composition's
# manifest at `caisson-core.libManifest`, projects the `libOverlays`
# and `modules` flake outputs from it, and defaults flake-parts'
# `systems` from the `systems` the composition declared), and the
# `flake-parts` library mirror.
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
  closure-lib,
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

  overlay =
    final: prev:
    let

      selection = final.caisson.integrations;

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
      # out (`lib.mkFlake`, `flakeModules`) is flake-parts' machinery
      # on caisson's library, with no second nixpkgs lib inside it.
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

      manifest =
        if (final.caisson-core.libManifest or null) != null then
          final.caisson-core.libManifest
        else
          throw ''
            caisson.flake-parts.mkConfiguration projects a composition's manifest into flake
            outputs, but this composed library carries no manifest at
            `caisson-core.libManifest`. Compose the library with
            caisson-core.mkLib, which captures one.
          '';

      # The `mkFlake` call: the manifest's inputs, the special
      # arguments and the module location when the flake is named,
      # beside the flake-parts it runs on and the module it evaluates.
      compose =
        {

          configModule,

          # The flake-parts source; resolved from the composition's
          # declarations when absent.
          ecosystemSrc ? null,

          # Selection over the flake class of the registry; the default
          # default is every entry named `default`.
          moduleImports ? selection.defaultModuleImports,

          # Package sets for the flake evaluation itself, handed to the
          # flake-class modules as the `pkgSets` special argument. Per
          # system package sets are the nixpkgs integration's business
          # (caisson.nixpkgs.pkgSets); this is the flake-level slot the
          # other integrations also carry.
          pkgSets ? null,

          specialArgs ? { },

          ...
        }:
        let

          flakeParts = if ecosystemSrc == null then flakePartsDefault else flakePartsFor ecosystemSrc;

          # The flake class of the registry, the same source every
          # adapter selects from, so modules arriving by any channel
          # (local registration, overlay contribution, consumed
          # project) are selectable here.
          registry = final.caisson-core.modules.flake or { };

          # The framework module of the class: the core of caisson
          # itself, read from the closure so it is there however this
          # integration was registered, plus every `core` the
          # composition registered.
          frameworkModules = [
            closure-lib.caisson-core.modules.flake.core
          ]
          ++ selection.coreModules registry;

          importedModules = moduleImports registry;

          # The name this configuration holds: the namespace the
          # composition declares on mkLib, since a flake evaluation has
          # no parent to declare it under an attribute.
          name = manifest.name or null;

        in
        {
          inherit flakeParts;
          # Exported modules are keyed by flake-parts' moduleLocation,
          # which defaults to self.outPath, a rev-sensitive identity, so
          # consumers composing this flake's modules from two different
          # revs (e.g. directly and via a sibling whose lock is one bump
          # behind) collect two copies of the same option declarations
          # and fail with "option ... is already declared". The
          # composition's namespace is rev-independent, so such copies
          # deduplicate. It comes from the manifest rather than the
          # module evaluation because moduleLocation is consumed before
          # that evaluation exists.
          # flake-parts' `inputs` are the composition's pinned sources;
          # `evaluate` adds `self`.
          ecosystemArgs = (if name != null then { moduleLocation = name; } else { }) // {
            inputs = manifest.sources;
            specialArgs = {
              lib = final;
            }
            // (if pkgSets != null then { inherit pkgSets; } else { })
            // specialArgs;
          };
          module = {
            imports = [
              flakeParts.flakeModules.flakeModules
              flakeParts.flakeModules.modules
            ]
            ++ frameworkModules
            ++ importedModules
            ++ [ configModule ];
          };
        };

      # flake-parts reads the flake's `self` from `inputs.self`, and its
      # modules take `self` and `self'` as arguments. The integration
      # ties that knot the way Nix does for a flake: `self` is the
      # evaluation's outputs with the root's source info (out path,
      # revision, last-modified) beside them, and `self.inputs` the
      # pinned sources. A composition with no root names no tree, so
      # its `self` has no out path. An `inputs` handed in through the
      # WithEcosystemArgs twin that carries its own `self` is taken as
      # it is.
      evaluate =
        composed: callArgs:
        let
          given = callArgs.inputs or { };
          root = manifest.root or null;
          # The root's source-info fields that name something: a flake's
          # `self` carries only the fields its tree has, so a reader of
          # `self.rev or …` sees a dirty tree as Nix hands it over.
          sourceInfo = if root == null then { } else final.filterAttrs (_: value: value != null) root;
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
          outputs = composed.flakeParts.lib.mkFlake (callArgs // { inherit inputs; }) composed.module;
        in
        outputs;

      evaluation = selection.mkEvaluation { inherit compose evaluate; };

      integration = selection.mkIntegration {
        name = "flake-parts";
        class = "flake";
        # `compose` destructures `configModule` without a default and
        # supplies the value of every optional argument left out. What
        # mkFlake takes beyond these comes from the composition's
        # manifest, through caisson-core.mkLib: the flake's `inputs`
        # (`self` among them) and its `moduleLocation`, the namespace
        # the composition declares, which is also the name of the
        # configuration.
        mkConfiguration =
          {
            # The configuration's module. Further modules of the class
            # are selected with `moduleImports`, from the registry.
            configModule,
            # The package sets for the flake evaluation itself, handed
            # to the flake-class modules as the `pkgSets` special
            # argument.
            pkgSets ? null,
            # The flake-parts source; resolved from the composition's
            # declarations when absent.
            ecosystemSrc ? null,
            # The selection over the flake class of the registry; every
            # entry named `default` when absent.
            moduleImports ? null,
            # Extra module arguments, merged over the ones the framework
            # supplies.
            specialArgs ? null,
          }@args:
          evaluation args;
        # The same arguments and `ecosystemArgs`, the evaluator's
        # arguments merged over the composed call last.
        mkConfigurationWithEcosystemArgs =
          {
            configModule,
            pkgSets ? null,
            ecosystemSrc ? null,
            moduleImports ? null,
            specialArgs ? null,
            ecosystemArgs ? null,
          }@args:
          evaluation args;
        extra = {
          inherit types;
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
