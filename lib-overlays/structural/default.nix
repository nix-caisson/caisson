# SPDX-License-Identifier: MIT
#
# The structural integration: the empty integration, wrapping
# no ecosystem. Its class, `structural`, is defined by caisson itself,
# since no ecosystem owns a plain tree of configurations, and it
# carries nothing but caisson's core module: the manifest, the
# configurations declared beneath, the registry selectors and
# `caisson.exports`. Its evaluator is the module system of the composed
# library, `evalModules`. A structural configuration is the top of a
# repository whose point is what it exports, and `default.nix` returns
# what `mkTopConfiguration` returns from it; it is also a layer at any
# depth, declared beneath another configuration under
# `caisson.structural.configurations`.
{
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

      # The evaluator's call, on the lib of the view being evaluated:
      # the framework modules of the class, the selection and the
      # configuration's module, with the composition's pinned sources
      # as the `inputs` special argument. `ecosystemArgs`, which only
      # the twin's pattern admits, is merged over the call last.
      evaluate =
        args:
        { lib, manifest }:
        let
          selection = lib.caisson.integrations;
          registry = lib.caisson-core.modules.structural or { };

          # The framework module of the class.
          frameworkModules = selection.frameworkModules "structural" registry;

          moduleImports = selection.moduleImportsOf "structural" { inherit lib manifest; } args;

          # The configuration's module: the module passed, else the
          # configuration registered under the configuration's name
          # (`configs/structural/<name>`), else none.
          name = manifest.name or null;
          registered = lib.caisson-core.configs.structural or { };
          configModule =
            if (args.configModule or null) != null then
              args.configModule
            else if name != null then
              registered.${name} or null
            else
              null;

          evaluated = lib.evalModules (
            {
              class = "structural";
              specialArgs = {
                inherit lib;
                inputs = manifest.sources;
              }
              // (if (args.pkgSets or null) != null then { inherit (args) pkgSets; } else { })
              // (if (args.specialArgs or null) != null then args.specialArgs else { });
              modules =
                frameworkModules
                ++ moduleImports registry
                ++ (if configModule == null then [ ] else [ configModule ]);
            }
            // (if (args.ecosystemArgs or null) != null then args.ecosystemArgs else { })
          );
        in
        {
          value = evaluated;
        };

      configuration =
        args:
        final.caisson.integrations.mkModuleConfiguration {
          type = "structural";
          selectPkgs = args.selectPkgs or null;
          evaluate = evaluate args;
        };

      # What a tool reads from a top: the registries it exports and the
      # configurations declared beneath it, each published under the
      # output attribute set its integration declares and named from
      # its path (`nixosConfigurations.<name>`), with the manifest
      # beside them for `manifestOf` and `topside --file`. A top has no
      # parent to declare it under an attribute, so its name is the name
      # the composition declares on mkLib.
      mkTopConfiguration =
        rawArgs:
        let
          manifest = final.caisson-core.finalizeTop (final.caisson.structural.mkConfiguration rawArgs);
          exports = manifest.outputs.exports;
        in
        builtins.removeAttrs exports [ "configurations" ]
        // final.caisson.integrations.publish exports.configurations
        // {
          caisson.manifest = manifest;
        };

      integration = final.caisson.integrations.mkIntegration {
        name = "structural";
        class = "structural";
        # What these return is a configuration, a function of
        # `{ name, parent }`: the parent that declares it under
        # `caisson.structural.configurations.<name>` finalizes it, and
        # `mkTopConfiguration` finalizes it at a top. The integration
        # wraps no ecosystem, so there is no `ecosystemSrc` here.
        mkConfiguration =
          {
            # The configuration's module. When absent, the configuration
            # registered under the configuration's name
            # (`lib.caisson-core.configs.structural.<name>`), if any.
            # Further modules of the class are selected with
            # `moduleImports`, from the registry.
            configModule ? null,
            # The package sets, handed to the modules as the `pkgSets`
            # special argument.
            pkgSets ? null,
            # The package set the configurations beneath this one run
            # on: a function that receives the package sets available
            # to each, by package config name, and returns the set to
            # run on. It holds for every configuration beneath that
            # selects none.
            selectPkgs ? null,
            # The selection over the structural class of the registry.
            # It replaces the default of the class, which is every
            # entry named `default` followed by what the
            # configurations above added.
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
            selectPkgs ? null,
            moduleImports ? null,
            extraModuleImports ? null,
            specialArgs ? null,
            ecosystemArgs ? null,
          }@args:
          configuration args;
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
