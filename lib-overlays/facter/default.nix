# SPDX-License-Identifier: MIT
#
# The facter integration, the upstream-compatible facter integration:
# it owns the `facter` class. A facter configuration is a hardware
# report as nixos-facter writes it, `facter.json`, named by the one
# option of the class, `reportPath`. It declares the NixOS
# configurations that run on that hardware under
# `caisson.nixos.configurations`.
#
# The default module of the class adds caisson's NixOS module
# `facter-hardware` to the NixOS configurations declared inside it.
# That module sets nixpkgs' `hardware.facter.reportPath` to the report,
# the line a NixOS configuration written for nixos-facter carries, so
# nixpkgs' `hardware.facter` module reads the file as it does for any
# NixOS configuration.
#
# The outputs are `reportPath` and `report`, the content of the file. A
# facter configuration is published under no output attribute set.
# For a report extended with options of a project, and checked against
# the report versions caisson knows, see the caisson-facter integration.
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
      context = "lib.caisson.facter";

      # The option of the class: the report file.
      reportOptions = final.caisson.integrations.caissonModule {
        key = "caisson.facter.reportOptions";
        file = "caisson-facter:reportOptions";
        module =
          { lib, ... }:
          {
            options.reportPath = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = ''
                The hardware report nixos-facter writes, `facter.json`, which
                the NixOS configurations declared inside this configuration
                get as `hardware.facter.reportPath`.
              '';
            };
          };
      };

      evaluate =
        args:
        { lib, manifest }:
        let
          selection = lib.caisson.integrations;
          registry = lib.caisson.modules.facter or { };
          frameworkModules = selection.frameworkModules "facter" registry;
          moduleImports = selection.moduleImportsOf "facter" { inherit lib manifest; } args;

          # The configuration's module: the module passed, else the
          # configuration registered under the configuration's name
          # (`configs/facter/<name>`), else none.
          name = manifest.name or null;
          configModule = selection.configModuleOf {
            inherit lib name;
            class = "facter";
            configModule = args.configModule or null;
          };

          moduleList = [
            reportOptions
          ]
          ++ frameworkModules
          ++ moduleImports registry
          ++ (if configModule == null then [ ] else [ configModule ]);

          evaluated = lib.evalModules (
            {
              class = "facter";
              specialArgs = {
                inherit lib;
              }
              // (if (args.specialArgs or null) != null then args.specialArgs else { });
              modules = moduleList;
            }
            // (if (args.ecosystemArgs or null) != null then args.ecosystemArgs else { })
          );
          inherit (evaluated.config) reportPath;
        in
        {
          value = evaluated;
          # What evalModules received: the report option, the
          # framework module of the class, the modules selected from
          # the registry and the configuration's module. The report is
          # data read from `reportPath`, not a module list, so there is
          # no ecosystem module list here.
          modules = moduleList;
          outputs = {
            inherit reportPath;
            report =
              if reportPath == null then
                throw "${context}: the facter configuration `${toString name}` names no `reportPath`."
              else
                builtins.fromJSON (builtins.readFile reportPath);
          };
        };

      configuration =
        args:
        final.caisson.integrations.mkModuleConfiguration {
          selection = {
            class = "facter";
            inherit args;
          };
          type = "facter";
          defaultPkgs = args.defaultPkgs or null;
          evaluate = evaluate args;
        };

      integration = final.caisson.integrations.mkIntegration {
        name = "facter";
        class = "facter";
        # What these return is a configuration, a function of
        # `{ name, parent }`: the parent that declares it under
        # `caisson.facter.configurations.<name>` finalizes it.
        mkConfiguration =
          {
            # The facter configuration's module: `reportPath`, and the
            # NixOS configurations that run on the hardware under
            # `caisson.nixos.configurations`. When absent, the
            # configuration registered under the configuration's name
            # (`lib.caisson.configs.facter.<name>`), if any. Further
            # modules of the class are selected with `moduleImports`,
            # from the registry.
            configModule ? null,
            # The package set the configurations beneath this one run
            # on: a function that receives the package sets available
            # to each, by package config name, and returns the set to
            # run on.
            defaultPkgs ? null,
            # The selection over the facter class of the registry. It
            # replaces the default of the class, which is every entry
            # named `default` followed by what the configurations above
            # added.
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
        facter = integration.namespace;
      };
    };

}
