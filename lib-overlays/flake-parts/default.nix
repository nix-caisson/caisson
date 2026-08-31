# SPDX-License-Identifier: MIT
#
# The flake-parts integration: projecting a composition into flake
# outputs. A peer of the other integrations, it carries mkFlake, the
# `flake` module class (mkFlakeModule), the option types (option
# types are this integration's medium), the export machinery (the
# core flake-parts module reads the composition's manifest at
# `caisson-core.manifest` and projects the `libOverlays` and
# `modules` flake outputs from it), and the `flake-parts` library
# mirror.
#
# This closes over the inputs of the flake where this overlay is
# defined, i.e. caisson: the flake-parts pin used to evaluate
# consumers' flake modules is caisson's own.
{ closure-inputs, ... }:

{

  imports = [ ];

  overlay =
    final: prev:
    let

      isLibOverlay =
        v:
        builtins.isAttrs v
        && builtins.hasAttr "overlay" v
        && builtins.isFunction v.overlay
        && builtins.isList (v.imports or [ ])
        && builtins.all isLibOverlay (v.imports or [ ]);

      types = ((prev.caisson or { }).types or { }) // {

        libOverlay = final.mkOptionType {
          name = "libOverlay";
          description = "library overlay ({ imports ? [ ], overlay })";
          descriptionClass = "noun";
          check = isLibOverlay;
        };

        # The manifest type: structural, checked on the export side
        # only. Producers validate their own manifests in their own
        # CI; consumers assume shape.
        manifest = final.mkOptionType {
          name = "caissonManifest";
          description = "caisson-core manifest ({ inputs, modules, libOverlays, ecosystems, projects })";
          descriptionClass = "noun";
          check =
            v:
            builtins.isAttrs v
            && builtins.isAttrs (v.inputs or null)
            && builtins.isAttrs (v.ecosystems or { })
            && builtins.isAttrs (v.projects or { })
            && builtins.isAttrs (v.modules or null)
            && builtins.all builtins.isAttrs (builtins.attrValues v.modules)
            && builtins.isAttrs (v.libOverlays or null)
            && builtins.all isLibOverlay (builtins.attrValues v.libOverlays);
        };

      };

      mkFlake =
        args@{

          configModule,

          moduleImports ? modules: modules,

          # The flake's canonical name. Exported modules are keyed by
          # flake-parts' moduleLocation, which defaults to self.outPath,
          # a rev-sensitive identity, so consumers composing this flake's
          # modules from two different revs (e.g. directly and via a sibling
          # whose lock is one bump behind) collect two copies of the same
          # option declarations and fail with "option ... is already
          # declared". Passing the name here makes module identity
          # rev-independent so such copies deduplicate. Also provides the
          # default for caisson.configInfo.configName, keeping the name
          # single-sourced. It must be an argument rather than (only) module
          # config because moduleLocation is consumed before the module eval
          # exists.
          name ? null,

          ...
        }:
        (
          if builtins.hasAttr "inputs" args then
            builtins.abort "inputs were passed to mkFlake. This is an easy mistake to make, but they should be passed to mkLib."
          else
            let

              manifest =
                final.caisson-core.manifest or (throw ''
                  caisson.mkFlake projects a composition's manifest into flake
                  outputs, but this composed library carries no manifest at
                  `caisson-core.manifest`. Compose the library with
                  caisson-core.mkLib, which captures one.
                '');

              filteredArgs = builtins.removeAttrs args [
                "configModule"
                "modules"
                "moduleImports"
                "name"
              ];

              finalArgs =
                (if name != null then { moduleLocation = name; } else { })
                // filteredArgs
                // {
                  inputs = manifest.inputs;
                  specialArgs = {
                    lib = final;
                  }
                  // filteredArgs.specialArgs or { };
                };

              # Selection over the flake class of the registry, the
              # same source every adapter selects from, so modules
              # arriving by any channel (local registration, overlay
              # contribution, consumed project) are selectable here.
              importedModules = moduleImports (final.caisson-core.modules.flake or { });

              finalModule = (
                { lib, ... }:
                {
                  imports = [
                    closure-inputs.flake-parts.flakeModules.flakeModules
                    closure-inputs.flake-parts.flakeModules.modules
                    ../../modules/flake-parts/core
                  ]
                  ++ (builtins.attrValues importedModules)
                  ++ [ configModule ]
                  ++ (if name != null then [ { caisson.configInfo.configName = lib.mkDefault name; } ] else [ ]);
                }
              );

            in
            closure-inputs.flake-parts.lib.mkFlake finalArgs finalModule
        );

    in
    {

      caisson = (prev.caisson or { }) // {
        inherit mkFlake types;
        mkFlakeModule = final.caisson-core.mkModule "flake";
      };

      flake-parts = (prev.flake-parts or { }) // closure-inputs.flake-parts.lib;

    };

}
