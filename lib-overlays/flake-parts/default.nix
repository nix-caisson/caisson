# SPDX-License-Identifier: MIT
#
# The flake-parts integration: projecting a composition into flake
# outputs. A peer of the other integrations, it carries mkConfiguration, the
# `flake` module class (mkModule), the option types (option
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

      prevNs = (prev.caisson or { }).flake-parts or { };

      types = (prevNs.types or { }) // {

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

      # flake-parts' own mkFlake arguments this entry point composes are
      # refused with a pointer to the caisson argument; the rest forward.
      accepted = [
        "configModule"
        "moduleImports"
        "name"
        "specialArgs"
        "pkgSets"
      ];
      hints = {
        inputs = "the flake's inputs come from the composition's manifest; pass them to caisson-core.mkLib.";
        self = "the flake's own outputs come from the composition's manifest; pass inputs (self included) to caisson-core.mkLib.";
        modules = "pass the configuration's module as `configModule`; registered flake-class modules are selected with `moduleImports`.";
        moduleLocation = "pass the flake's canonical name as `name`.";
      };
      checkArgs = import ../check-args.nix {
        context = "lib.caisson.flake-parts.mkConfiguration";
        inherit accepted hints;
        open = "lib.caisson.flake-parts.mkConfigurationUnsupervised";
      };
      checkOpenArgs = import ../check-args.nix {
        context = "lib.caisson.flake-parts.mkConfigurationUnsupervised";
        accepted = accepted ++ [ "evaluatorArgs" ];
        inherit hints;
      };
      mkConfiguration = rawArgs: mkConfigurationChecked (checkArgs rawArgs);
      # The same composition, then `evaluatorArgs` merged over the
      # flake-parts mkFlake call verbatim: everything it takes (inputs,
      # specialArgs, self, moduleLocation) can be set or replaced there.
      mkConfigurationUnsupervised = rawArgs: mkConfigurationChecked (checkOpenArgs rawArgs);
      mkConfigurationChecked =
        args@{

          configModule,

          moduleImports ? builtins.attrValues,

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

          # Package sets for the flake evaluation itself, handed to the
          # flake-class modules as the `pkgSets` special argument. Per
          # system package sets are the nixpkgs integration's business
          # (caisson.nixpkgs.pkgSets); this is the flake-level slot the
          # other integrations also carry.
          pkgSets ? null,

          specialArgs ? { },

          evaluatorArgs ? { },
        }:
        (
          let

            manifest =
              final.caisson-core.manifest or (throw ''
                caisson.flake-parts.mkConfiguration projects a composition's manifest into flake
                outputs, but this composed library carries no manifest at
                `caisson-core.manifest`. Compose the library with
                caisson-core.mkLib, which captures one.
              '');

            finalArgs =
              (if name != null then { moduleLocation = name; } else { })
              // {
                inputs = manifest.inputs;
                specialArgs = {
                  lib = final;
                }
                // (if pkgSets != null then { inherit pkgSets; } else { })
                // specialArgs;
              }
              // evaluatorArgs;

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
                ++ importedModules
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
        flake-parts = prevNs // {
          inherit mkConfiguration mkConfigurationUnsupervised types;
          mkModule = final.caisson-core.mkModule "flake";
        };
      };

      flake-parts = (prev.flake-parts or { }) // closure-inputs.flake-parts.lib;

    };

}
