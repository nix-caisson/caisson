# SPDX-License-Identifier: MIT
#
# The terranix integration: it owns the `terranix` class and
# evaluates it with `terranixConfiguration` from the terranix flake. A
# terranix configuration is a Terraform configuration written as
# modules, evaluated per system, once for each system its parent evaluates its children for,
# on the package set selected for it.
#
# Its output is `json`, the `config.tf.json` file Terraform reads,
# which is also the value: `terranixConfiguration` returns that file
# with the evaluated `config` in its `passthru`. A configuration is
# published as `terranixConfigurations.<name>`, the name terranix's
# flake-parts module gives its configurations.
#
# terranix runs a separate module system on the library of its package
# set, so the modules receive the composed library as the `lib`
# argument while terranix merges and checks the options with the
# library of that package set. terranix returns only the configuration
# Terraform reads and its `_meta`, so caisson reads the `caisson`
# options through `_meta.caisson`, and no configurations can be
# declared inside a terranix configuration.
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

      resolveEcosystemSrc = final.caisson.integrations.resolveEcosystemSrc ecosystem;
      ecosystemAccountOf = final.caisson.integrations.ecosystemAccountOf ecosystem;
      ecosystem = {
        name = "terranix";
        context = "caisson.terranix";
      };

      assertTerranixEcosystemSrc =
        ecosystemSrc:
        if ecosystemSrc ? lib && ecosystemSrc.lib ? terranixConfiguration then
          ecosystemSrc
        else
          throw "${context} requires `ecosystemSrc.lib.terranixConfiguration`.";

      # The evaluator's call, on the lib and manifest the configuration is evaluated with:
      # `terranixConfiguration` over the framework modules, the
      # selection and the configuration's module, on the package set
      # selected for the configuration. `ecosystemArgs`, which only the
      # pattern of the `WithEcosystemArgs` variant admits, is merged over the call last; everything
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
          configModule = selection.configModuleOf {
            inherit lib name;
            class = "terranix";
            configModule = args.configModule or null;
          };

          # terranix returns the configuration with the keys Terraform
          # reads alone, and `_meta`, the metadata it passes through
          # without rendering it. caisson's options reach the result
          # there.
          metaModule = selection.caissonModule {
            key = "caisson.terranix.meta";
            file = "caisson-terranix:meta";
            module =
              { config, ... }:
              {
                _file = "caisson-terranix:meta";
                _meta.caisson = config.caisson;
              };
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
          # Where terranix came from, as `src` was resolved.
          ecosystems.terranix = ecosystemAccountOf {
            explicit = args.ecosystemSrc or null;
            manifest = lib.caisson-core.libManifest or { };
          };
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
          # caisson's options, from `_meta`. terranix keeps the evaluated
          # options to itself, so no configurations can be
          # declared inside a terranix configuration.
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
          # evaluation result for each system its parent evaluates its
          # children for.
          perSystem = true;
          defaultPkgs = args.defaultPkgs or null;
          inherit exportsTo;
          # Each evaluation result of a terranix configuration checks
          # that its `config.tf.json` file, the file Terraform reads,
          # builds.
          checks =
            { outputs, ... }:
            {
              json = {
                derivation = outputs.json;
                category = "build";
                description = "the `config.tf.json` file of the terranix configuration, which Terraform reads, builds";
              };
            };
          evaluate = evaluate args;
        };

      integration = final.caisson.integrations.mkIntegration {
        name = "terranix";
        class = "terranix";
        # A terranix configuration that is a caisson top, as a tool reads it:
        # the `config.tf.json` file, or the files by system where
        # the composition declares several systems.
        top = final.caisson.integrations.topValue;
        # What these return is a configuration, a function of
        # `{ name, parent }`: a parent that declares it under
        # `caisson.terranix.configurations.<name>` finalizes it, and
        # `mkTopConfiguration` finalizes it at a caisson top.
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
            # declared, by package config name, each for the system the
            # configuration is evaluated for, and returns the set to run on. When
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
