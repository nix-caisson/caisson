# SPDX-License-Identifier: MIT
#
# The disko integration, the upstream-compatible one: it owns the
# `disko` class. A disko configuration is a standalone disk layout: a
# module that sets `disko.devices`, and a file written for disko's
# `diskoConfigurations` is the configuration's module as it is.
#
# The layout is evaluated as disko evaluates a standalone layout:
# `evalModules` over `disko.devices`, typed with disko's type library,
# with the framework modules, the selection and the configuration's
# module beside it. The outputs are the layout product the native
# integration makes.
#
# A disko configuration is published as `diskoConfigurations.<name>`,
# as the native integration publishes it, and disko's command formats
# and mounts it from there with `disko --flake .#<name>`.
#
# disko's other form, a NixOS configuration that writes its layout as
# `disko.devices` and imports disko's NixOS module, is a NixOS
# configuration that selects caisson's `disko` NixOS module. A NixOS
# configuration installed onto a layout that is a separate
# configuration is declared inside a caisson-disko configuration.
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
    # The native disko integration, whose type library, devices option,
    # layout product and publishing this one builds on.
    ((mkLibOverlay ../caisson-disko) // { key = "caisson-disko"; })
  ];

  overlay =
    final: prev:
    let
      native = final.caisson.caisson-disko;

      # The evaluator's call, on the lib of the view being evaluated:
      # the devices option, the framework modules of the class, the
      # selection and the configuration's module, with the
      # composition's pinned sources as the `inputs` special argument.
      # `ecosystemArgs`, which only the twin's pattern admits, is merged
      # over the call last.
      evaluate =
        args:
        { lib, manifest }:
        let
          selection = lib.caisson.integrations;
          src = native.ecosystemSrcOf {
            explicit = args.ecosystemSrc or null;
            inherit manifest;
          };
          rootMountPoint = if (args.rootMountPoint or null) != null then args.rootMountPoint else "/mnt";
          diskoLib = native.diskoLibOf { inherit lib src rootMountPoint; };
          registry = lib.caisson.modules.disko or { };
          frameworkModules = selection.frameworkModules "disko" registry;
          moduleImports = selection.moduleImportsOf "disko" { inherit lib manifest; } args;

          # The configuration's module: the module passed, else the
          # configuration registered under the configuration's name
          # (`configs/disko/<name>`), else none.
          name = manifest.name or null;
          registered = lib.caisson.configs.disko or { };
          configModule =
            if (args.configModule or null) != null then
              args.configModule
            else if name != null then
              registered.${name} or null
            else
              null;

          moduleList = [
            (native.devicesOptions diskoLib)
          ]
          ++ frameworkModules
          ++ moduleImports registry
          ++ (if configModule == null then [ ] else [ configModule ]);

          evaluated = lib.evalModules (
            {
              class = "disko";
              specialArgs = {
                inherit lib;
                inputs = manifest.sources;
              }
              // (if (args.pkgSets or null) != null then { inherit (args) pkgSets; } else { })
              // (if (args.specialArgs or null) != null then args.specialArgs else { });
              modules = moduleList;
            }
            // (if (args.ecosystemArgs or null) != null then args.ecosystemArgs else { })
          );
        in
        {
          value = evaluated;
          # What evalModules received: the devices option, the
          # framework module of the class, the modules selected from
          # the registry and the configuration's module. disko's type
          # library builds the devices option; it reads no module
          # list of disko.
          modules = moduleList;
          outputs = native.layoutOf {
            context = "lib.caisson.disko";
            assertions = [ ];
            inherit rootMountPoint;
            devices = evaluated.config.disko.devices;
            checked = args.checked or false;
          };
        };

      configuration =
        args:
        final.caisson.integrations.mkModuleConfiguration {
          type = "disko";
          defaultPkgs = args.defaultPkgs or null;
          inherit (native) exportsTo;
          evaluate = evaluate args;
        };

      integration = final.caisson.integrations.mkIntegration {
        name = "disko";
        class = "disko";
        # What these return is a configuration, a function of
        # `{ name, parent }`: the parent that declares it under
        # `caisson.disko.configurations.<name>` finalizes it.
        mkConfiguration =
          {
            # The disko configuration's module: `disko.devices`, as a
            # file written for disko sets it. When absent, the
            # configuration registered under the configuration's name
            # (`lib.caisson.configs.disko.<name>`), if any. Further
            # modules of the class are selected with `moduleImports`,
            # from the registry.
            configModule ? null,
            # The package sets, handed to the modules as the `pkgSets`
            # special argument.
            pkgSets ? null,
            # The package set the layout's scripts are built with, and
            # the one the configurations beneath this one run on: a
            # function that receives the package sets available, by
            # package config name, and returns the set to run on.
            defaultPkgs ? null,
            # The disko flake or source tree; resolved from the
            # composition's declarations when absent.
            ecosystemSrc ? null,
            # The selection over the disko class of the registry. It
            # replaces the default of the class, which is every entry
            # named `default` followed by what the configurations above
            # added.
            moduleImports ? null,
            # A selection added to that selection, whichever it is.
            extraModuleImports ? null,
            # Extra module arguments, merged over those the framework
            # supplies.
            specialArgs ? null,
            # The directory the mount script mounts the layout under;
            # "/mnt" when absent.
            rootMountPoint ? null,
            # Whether the scripts are checked with shellcheck when they
            # are built; false when absent.
            checked ? null,
          }@args:
          configuration args;
        # The same arguments and `ecosystemArgs`, the evaluator's
        # arguments merged over the composed call last.
        mkConfigurationWithEcosystemArgs =
          {
            configModule ? null,
            pkgSets ? null,
            defaultPkgs ? null,
            ecosystemSrc ? null,
            moduleImports ? null,
            extraModuleImports ? null,
            specialArgs ? null,
            rootMountPoint ? null,
            checked ? null,
            ecosystemArgs ? null,
          }@args:
          configuration args;
      };
    in
    {
      caisson = (prev.caisson or { }) // {
        disko = integration.namespace;
      };
    };

}
