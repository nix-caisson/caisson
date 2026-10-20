# SPDX-License-Identifier: MIT
#
# The terranix integration: it owns the `terranix` class and
# evaluates it with `terranixConfiguration` from the terranix flake. A
# terranix configuration is a Terraform configuration written as
# modules, evaluated per system, once for each system in force where it is declared,
# on the package set selected for it.
#
# Its output is `json`, the `config.tf.json` file Terraform reads,
# which is also the value: `terranixConfiguration` returns that file
# with the evaluated `config` in its `passthru`. A configuration is
# published as `terranixConfigurations.<name>`, the name terranix's
# flake-parts module gives its configurations.
#
# terranix runs its own module system on the library of its package
# set, so the composed library reaches the modules as the `lib`
# argument while terranix merges and checks the options with its own.
# terranix returns only the configuration Terraform reads and its
# `_meta`, so caisson reads its own options through `_meta.caisson`,
# and a terranix configuration holds no configurations beneath it.
{
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
      context = "lib.caisson.terranix.mkConfiguration";

      resolveEcosystemSrc = final.caisson.integrations.resolveEcosystemSrc {
        name = "terranix";
        context = "caisson.terranix";
      };

      assertTerranixEcosystemSrc =
        ecosystemSrc:
        if ecosystemSrc ? lib && ecosystemSrc.lib ? terranixConfiguration then
          ecosystemSrc
        else
          throw "${context} requires `ecosystemSrc.lib.terranixConfiguration`.";

      # The evaluator's call, on the view being evaluated:
      # `terranixConfiguration` over the framework modules, the
      # selection and the configuration's module, on the package set
      # selected for the configuration. `ecosystemArgs`, which only the
      # twin's pattern admits, is merged over the call last; everything
      # `terranixConfiguration` takes (`pkgs`, `modules`, `extraArgs`,
      # `strip_nulls`) can be set or replaced there.
      evaluate =
        args:
        { lib, manifest }:
        let
          selection = lib.caisson.integrations;
          src = assertTerranixEcosystemSrc (resolveEcosystemSrc {
            explicit = args.ecosystemSrc or null;
            manifest = lib.caisson-core.libManifest or { };
          });

          name = manifest.name or null;
          inherit (manifest) system;
          what =
            if name != null then
              "the terranix configuration `${name}` for ${system}"
            else
              "this terranix configuration for ${system}";

          pkgSets = selection.pkgSetsForSystem { inherit context what; } manifest system;
          pkgs = selection.pkgSetOf { inherit context what; } manifest pkgSets;

          registry = lib.caisson.modules.terranix or { };
          frameworkModules = selection.frameworkModules "terranix" registry;
          moduleImports = selection.moduleImportsOf "terranix" { inherit lib manifest; } args;

          # The configuration's module: the module passed, else the
          # configuration registered under the configuration's name
          # (`configs/terranix/<name>`), else none.
          registered = lib.caisson.configs.terranix or { };
          configModule =
            if (args.configModule or null) != null then
              args.configModule
            else if name != null then
              registered.${name} or null
            else
              null;

          # terranix returns the configuration with the keys Terraform
          # reads alone, and `_meta`, the metadata it passes through
          # without rendering it. caisson's options reach the result
          # there.
          metaModule =
            { config, ... }:
            {
              _file = "caisson-terranix:meta";
              _meta.caisson = config.caisson;
            };

          moduleList =
            frameworkModules
            ++ moduleImports registry
            ++ (if configModule == null then [ ] else [ configModule ])
            ++ [ metaModule ];

          value = src.lib.terranixConfiguration (
            {
              inherit pkgs;
              modules = moduleList;
              # terranix names the special arguments `extraArgs`.
              extraArgs = {
                inherit lib pkgSets;
              }
              // (if (args.specialArgs or null) != null then args.specialArgs else { });
            }
            // (if (args.ecosystemArgs or null) != null then args.ecosystemArgs else { })
          );
        in
        {
          inherit value;
          # What `terranixConfiguration` received: terranix's module
          # list, then the modules of the composition.
          modules = [
            (final.caisson.integrations.ecosystemUnit {
              key = "terranix";
              project = "terranix";
              file = null;
            })
          ]
          ++ moduleList;
          # What Terraform reads: the `config.tf.json` file.
          outputs.json = value;
          # caisson's options, from `_meta`. terranix keeps the options
          # of the evaluation to itself, so a terranix configuration
          # holds no configurations beneath it.
          config.caisson = value._meta.caisson;
          options = { };
        };

      # A terranix configuration is published as
      # `terranixConfigurations.<name>`, its `config.tf.json` file.
      exportsTo = {
        attrset = "terranixConfigurations";
        value = manifest: manifest.value;
      };

      configuration =
        args:
        final.caisson.integrations.mkModuleConfiguration {
          selection = {
            class = "terranix";
            inherit args;
          };
          type = "terranix";
          # A terranix configuration is evaluated per system: it has an
          # evaluation for every system in force where it is declared.
          perSystem = true;
          defaultPkgs = args.defaultPkgs or null;
          inherit exportsTo;
          evaluate = evaluate args;
        };

      integration = final.caisson.integrations.mkIntegration {
        name = "terranix";
        class = "terranix";
        # A terranix configuration that is a top, as a tool reads it:
        # the `config.tf.json` file, or the files by system where
        # several systems are in force.
        top = final.caisson.integrations.topValue;
        # What these return is a configuration, a function of
        # `{ name, parent }`: a parent that declares it under
        # `caisson.terranix.configurations.<name>` finalizes it, and
        # `mkTopConfiguration` finalizes it at a top.
        mkConfiguration =
          {
            # The configuration's module. When absent, the configuration
            # registered under the configuration's name
            # (`lib.caisson.configs.terranix.<name>`), if any. Further
            # modules of the class are selected with `moduleImports`,
            # from the registry.
            configModule ? null,
            # The terranix flake; resolved from the composition's
            # declarations when absent.
            ecosystemSrc ? null,
            # The package set the configuration runs on: a function
            # that receives the package sets available where it is
            # declared, by package config name, each for the system of
            # the evaluation, and returns the set to run on. When
            # absent, the selection of the nearest configuration above,
            # and the set named `default` where none above selects.
            defaultPkgs ? null,
            # The selection over the terranix class of the registry. It
            # replaces the default of the class, which is every entry
            # named `default` followed by what the configurations
            # above added.
            moduleImports ? null,
            # A selection added to that selection, whichever it is.
            extraModuleImports ? null,
            # Extra module arguments, merged over those the framework
            # supplies; terranix names these `extraArgs`.
            specialArgs ? null,
          }@args:
          configuration args;
        # The same arguments and `ecosystemArgs`, the evaluator's
        # arguments merged over the composed call last.
        mkConfigurationWithEcosystemArgs =
          {
            configModule ? null,
            ecosystemSrc ? null,
            defaultPkgs ? null,
            moduleImports ? null,
            extraModuleImports ? null,
            specialArgs ? null,
            ecosystemArgs ? null,
          }@args:
          configuration args;
      };
    in
    {
      caisson = (prev.caisson or { }) // {
        terranix = integration.namespace;
      };
    };

}
