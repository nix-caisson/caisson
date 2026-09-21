# SPDX-License-Identifier: MIT
#
# The structural integration: the empty integration, wrapping no
# ecosystem. Its class, `structural`, is one caisson defines itself,
# since no ecosystem owns a plain tree of configurations, and it
# carries nothing but caisson's core module: the manifest, the
# registry selectors and `caisson.exports`. A structural configuration
# is the top of a repository whose point is what it exports, and
# `default.nix` returns what `mkTopConfiguration` returns from it.
{ closure-lib, entries, ... }:

{

  imports = [ entries.nixpkgs-lib ];

  overlay =
    final: prev:
    let

      prevNs = (prev.caisson or { }).structural or { };

      selection = import ../../helpers/registry-selection.nix;

      accepted = [
        "configModule"
        "moduleImports"
        "name"
        "specialArgs"
        "pkgSets"
      ];
      hints = {
        modules = "pass the configuration's module as `configModule`; registered structural modules are selected with `moduleImports`.";
      };
      checkArgs = import ../../helpers/check-args.nix {
        context = "lib.caisson.structural.mkConfiguration";
        inherit accepted hints;
      };

      mkConfiguration = rawArgs: mkConfigurationChecked (checkArgs rawArgs);

      mkConfigurationChecked =
        {

          configModule,

          # Selection over the structural class of the registry; the
          # default default is every entry named `default`.
          moduleImports ? selection.defaultModuleImports,

          # The configuration's canonical name; the default for
          # caisson.configInfo.configName.
          name ? null,

          # Package sets handed to the modules as the `pkgSets` special
          # argument, the slot every integration carries.
          pkgSets ? null,

          specialArgs ? { },

        }:
        let

          manifest =
            if (final.caisson-core.libManifest or null) != null then
              final.caisson-core.libManifest
            else
              throw ''
                caisson.structural.mkConfiguration evaluates over a composition's manifest,
                but this composed library carries no manifest at
                `caisson-core.libManifest`. Compose the library with
                caisson-core.mkLib, which captures one.
              '';

          registry = final.caisson-core.modules.structural or { };

          # The framework module of the class: caisson's own core, read
          # from the closure so it is there however this integration was
          # registered, plus every `core` the composition registered.
          frameworkModules = [
            closure-lib.caisson-core.modules.structural.core
          ]
          ++ selection.coreModules registry;

          importedModules = moduleImports registry;

          evaluated = final.evalModules {
            class = "structural";
            specialArgs = {
              lib = final;
              inputs = manifest.inputs;
            }
            // (if pkgSets != null then { inherit pkgSets; } else { })
            // specialArgs;
            modules =
              frameworkModules
              ++ importedModules
              ++ [ configModule ]
              ++ (if name != null then [ { caisson.configInfo.configName = final.mkDefault name; } ] else [ ]);
          };

        in
        {
          value = evaluated.config;
          outputs = {
            exports = evaluated.config.caisson.exports;
          };
        };

      # What a tool reads from a top: the exports, with the manifest
      # beside them for `manifestOf` and `topside --file`.
      mkTopConfiguration =
        rawArgs:
        let
          configuration = mkConfiguration rawArgs;
        in
        configuration.outputs.exports
        // {
          caisson.manifest = configuration.value.caisson.manifest;
        };

    in
    {

      caisson = (prev.caisson or { }) // {
        structural = prevNs // {
          inherit mkConfiguration mkTopConfiguration;
          mkModule = final.caisson-core.mkModule "structural";
        };
      };

    };

}
