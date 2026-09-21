# SPDX-License-Identifier: MIT
#
# The flake-parts integration: projecting a composition into flake
# outputs. A peer of the other integrations, it carries mkConfiguration, the
# `flake` module class (mkModule), the option types (option
# types are this integration's medium), the export machinery (the
# core flake-parts module reads the composition's manifest at
# `caisson-core.libManifest`, projects the `libOverlays` and
# `modules` flake outputs from it, and defaults flake-parts' `systems`
# from the `systems` the composition declared), and the `flake-parts`
# library mirror.
#
# flake-parts itself comes from the composition, resolved like every
# ecosystem (the explicit `ecosystemSrc`, `defaultEcosystemSrc.flake-parts`
# in the mkLib call, the entry named `flake-parts` in the inputs passed
# to mkLib),
# and is taken as a source: its flake.nix is called with the composed
# library standing in for its `nixpkgs-lib` input, so the module
# evaluation runs on the same library everything else in the
# composition does, never on a library flake-parts assembled for
# itself.
{ entries, ... }:

{

  imports = [ entries.nixpkgs-lib ];

  overlay =
    final: prev:
    let

      prevNs = (prev.caisson or { }).flake-parts or { };

      resolveEcosystemSrc = import ../resolve-ecosystem-src.nix {
        name = "flake-parts";
        context = "caisson.flake-parts";
        resolve = final.caisson-core.resolve;
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
      types = (prevNs.types or { }) // import ../../modules/core/types.nix { lib = final; };

      # flake-parts' own mkFlake arguments this entry point composes are
      # refused with a pointer to the caisson argument; the rest forward.
      accepted = [
        "configModule"
        "ecosystemSrc"
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
        open = "lib.caisson.flake-parts.mkConfigurationWithEcosystemArgs";
      };
      checkOpenArgs = import ../check-args.nix {
        context = "lib.caisson.flake-parts.mkConfigurationWithEcosystemArgs";
        accepted = accepted ++ [ "ecosystemArgs" ];
        inherit hints;
      };
      mkConfiguration = rawArgs: mkConfigurationChecked (checkArgs rawArgs);
      # The same composition, then `ecosystemArgs` merged over the
      # flake-parts mkFlake call verbatim: everything it takes (inputs,
      # specialArgs, self, moduleLocation) can be set or replaced there.
      mkConfigurationWithEcosystemArgs = rawArgs: mkConfigurationChecked (checkOpenArgs rawArgs);
      mkConfigurationChecked =
        args@{

          configModule,

          # The flake-parts source; resolved from the composition's
          # declarations when absent.
          ecosystemSrc ? null,

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

          ecosystemArgs ? { },
        }:
        (
          let

            flakeParts = if ecosystemSrc == null then flakePartsDefault else flakePartsFor ecosystemSrc;

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
              // ecosystemArgs;

            # Selection over the flake class of the registry, the
            # same source every adapter selects from, so modules
            # arriving by any channel (local registration, overlay
            # contribution, consumed project) are selectable here.
            importedModules = moduleImports (final.caisson-core.modules.flake or { });

            finalModule = (
              { lib, ... }:
              {
                imports = [
                  flakeParts.flakeModules.flakeModules
                  flakeParts.flakeModules.modules
                  ../../modules/flake-parts/core
                ]
                ++ importedModules
                ++ [ configModule ]
                ++ (if name != null then [ { caisson.configInfo.configName = lib.mkDefault name; } ] else [ ]);
              }
            );

          in
          flakeParts.lib.mkFlake finalArgs finalModule
        );

    in
    {

      caisson = (prev.caisson or { }) // {
        flake-parts = prevNs // {
          inherit mkConfiguration mkConfigurationWithEcosystemArgs types;
          mkModule = final.caisson-core.mkModule "flake";
        };
      };

      # The flake-parts library mirrored into the composed library,
      # from the composition's declared flake-parts; forced only when
      # read.
      flake-parts = (prev.flake-parts or { }) // flakePartsDefault.lib;

    };

}
