# SPDX-License-Identifier: MIT
#
# The structural integration: the empty integration, wrapping
# no ecosystem. Its class, `structural`, is one caisson defines itself,
# since no ecosystem owns a plain tree of configurations, and it
# carries nothing but caisson's core module: the manifest, the
# registry selectors and `caisson.exports`. Its evaluator is the module
# system of the composed library, `evalModules`. A structural
# configuration is the top of a repository whose point is what it
# exports, and `default.nix` returns what `mkTopConfiguration` returns
# from it.
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

      # The `evalModules` call: the framework modules of the class, the
      # selection and the configuration's module, over the manifest's
      # inputs. The configuration's name comes from the manifest,
      # through the core module.
      compose =
        args@{

          configModule,

          # Selection over the structural class of the registry; the
          # default default is every entry named `default`.
          moduleImports ? selection.defaultModuleImports,

          # Package sets handed to the modules as the `pkgSets` special
          # argument, the slot every integration carries.
          pkgSets ? null,

          specialArgs ? { },

          ...
        }:
        # The closed signature admits `ecosystemSrc` for every
        # integration; this one has no ecosystem to resolve it against.
        if args ? ecosystemSrc then
          throw "lib.caisson.structural takes no `ecosystemSrc`: the structural integration wraps no ecosystem."
        else
          let
            registry = final.caisson-core.modules.structural or { };

            # The framework module of the class: the core of caisson
            # itself, read from the closure so it is there however this
            # integration was registered, plus every `core` the
            # composition registered.
            frameworkModules = [
              closure-lib.caisson-core.modules.structural.core
            ]
            ++ selection.coreModules registry;
          in
          {
            ecosystemArgs = {
              class = "structural";
              specialArgs = {
                lib = final;
                inputs = manifest.inputs;
              }
              // (if pkgSets != null then { inherit pkgSets; } else { })
              // specialArgs;
              modules = frameworkModules ++ moduleImports registry ++ [ configModule ];
            };
          };

      evaluate =
        _composed: callArgs:
        let
          evaluated = final.evalModules callArgs;
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
          configuration = final.caisson.structural.mkConfiguration rawArgs;
        in
        configuration.outputs.exports
        // {
          caisson.manifest = configuration.value.caisson.manifest;
        };

      integration = selection.mkIntegration {
        name = "structural";
        class = "structural";
        hints = {
          name = "a configuration's name is the attribute its parent declares it under, or, with no parent, the namespace the composition declares; pass `namespace` to caisson-core.mkLib.";
        };
        inherit compose evaluate;
        extra = {
          inherit mkTopConfiguration;
        };
      };

    in
    contributeClasses prev integration.classes
    // {
      caisson = (prev.caisson or { }) // {
        structural = integration.namespace;
      };
    };

}
