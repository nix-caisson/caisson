# SPDX-License-Identifier: MIT
#
# The caisson-disko integration, the native disko integration: it owns
# the `caisson-disko` class. A disko configuration is a disk layout: a
# module of that class with `disko.devices`, disko's grammar for the
# disks, typed with disko's type library. It declares the NixOS
# configurations installed onto the layout the way any configuration
# declares NixOS configurations, under `caisson.nixos.configurations`,
# and it may declare none: a data array, a removable disk.
#
# The evaluation is caisson's own `evalModules` over that option, the
# framework modules, the selection and the configuration's module. It
# runs on the composed library, with the type library built from the
# disko source the composition declares. Its outputs are the layout
# product: the device tree as data, the NixOS settings the devices
# produce (`fileSystems`, `boot`, `swapDevices`), and the scripts that
# format, mount and destroy the disks, each a function of a package
# set. The class also declares `assertions`, which a module of the
# class uses to refuse a layout; every output fails with the messages
# of the assertions that do not hold.
#
# The default module of the class adds caisson's `caisson-disko-layout`
# NixOS module to the NixOS configurations declared inside the layout.
# That module gives a NixOS configuration the layout's `fileSystems`,
# `boot` and `swapDevices`, and nothing of disko itself: a NixOS
# configuration beneath a caisson-disko configuration carries no disko
# module, so the scripts that format and destroy the disks are not
# reachable from it. They are outputs of the layout alone.
#
# A disko configuration is published as `diskoConfigurations.<name>`,
# in the form disko's command reads: `disko.devices`, the evaluated
# device tree with disko's internal attributes left out.
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

      resolveEcosystemSrc = final.caisson.integrations.resolveEcosystemSrc ecosystem;
      ecosystem = {
        name = "disko";
        context = "caisson.caisson-disko";
      };

      # A disko source: a disko flake or a disko source tree, either of
      # which holds the type library at `lib/default.nix` and the NixOS
      # module at `module.nix`.
      assertDiskoEcosystemSrc =
        ecosystemSrc:
        let
          path = if builtins.isAttrs ecosystemSrc then ecosystemSrc.outPath or null else ecosystemSrc;
        in
        if path != null && builtins.pathExists "${path}/lib/default.nix" then
          ecosystemSrc
        else
          throw "lib.caisson.caisson-disko requires `ecosystemSrc` to be a disko flake or source tree (holding lib/default.nix).";

      # The disko source of a configuration: `explicit` when given, else
      # what the composition declares or pins under the name `disko`, as
      # recorded on `manifest`.
      ecosystemSrcOf =
        { explicit, manifest }:
        assertDiskoEcosystemSrc (resolveEcosystemSrc {
          inherit explicit manifest;
        });

      # Where that disko source came from, from the same arguments, as
      # a manifest records it under `ecosystems.disko`.
      ecosystemAccountOf =
        { explicit, manifest }:
        final.caisson.integrations.ecosystemAccountOf ecosystem { inherit explicit manifest; };

      # disko's type library, from the disko source, over `lib`. The
      # types are built from `rootMountPoint`, the directory the mount
      # script mounts the layout under.
      diskoLibOf =
        {
          lib,
          src,
          rootMountPoint,
        }:
        import "${src}/lib" { inherit lib rootMountPoint; };

      # The option a disko configuration is evaluated against: disko's
      # devices grammar, typed by disko's type library.
      devicesOptions =
        diskoLib:
        { lib, ... }:
        {
          options.disko.devices = lib.mkOption {
            type = diskoLib.toplevel;
            default = { };
            description = "The disk layout, in disko's devices grammar.";
          };
        };

      # The assertions of the class: a module of the class adds one to
      # refuse a layout, with a message saying why.
      assertionsOptions =
        { lib, ... }:
        {
          options.assertions = lib.mkOption {
            type = lib.types.listOf (
              lib.types.submodule {
                options = {
                  assertion = lib.mkOption {
                    type = lib.types.bool;
                    description = "Whether the layout is accepted.";
                  };
                  message = lib.mkOption {
                    type = lib.types.str;
                    description = "Why the layout is refused, when `assertion` is false.";
                  };
                };
              }
            );
            default = [ ];
            description = ''
              Conditions the layout must meet. Every output of the disko
              configuration fails with the message of each assertion that
              is false.
            '';
          };
        };

      # The device tree as data: disko's internal attributes, whose
      # names begin with `_`, and functions left out.
      stripInternal =
        value:
        if builtins.isAttrs value then
          final.concatMapAttrs (
            name: inner:
            if final.hasPrefix "_" name || builtins.isFunction inner then
              { }
            else
              { ${name} = stripInternal inner; }
          ) value
        else if builtins.isList value then
          builtins.map stripInternal (builtins.filter (inner: !builtins.isFunction inner) value)
        else
          value;

      # The layout product of an evaluated disko configuration, from
      # its `disko.devices`, the assertions it must meet, the mount
      # point its types were built from and whether its scripts are
      # checked with shellcheck. `context` names the integration in the
      # message of a refused layout.
      layoutOf =
        {
          context,
          devices,
          assertions,
          rootMountPoint,
          checked,
        }:
        let
          failed = builtins.map (assertion: assertion.message) (
            builtins.filter (assertion: !assertion.assertion) assertions
          );
          accepted =
            if failed == [ ] then
              devices
            else
              throw ''
                ${context}: the layout is refused:
                ${builtins.concatStringsSep "\n" (builtins.map (message: "- ${message}") failed)}
              '';
          serializableLayout = stripInternal accepted;
        in
        {
          inherit serializableLayout rootMountPoint;
          # The identity of the layout: the hash of the device tree as
          # data, so two evaluations that lower to the same disks have
          # the same hash.
          layoutHash = builtins.hashString "sha256" (builtins.toJSON serializableLayout);
          # The NixOS settings the devices produce, `fileSystems`,
          # `boot` and `swapDevices`, each a definition for a NixOS
          # option, which may be built with `mkMerge` or `mkIf`.
          nixosConfig = accepted._config;
          # disko's record of which device depends on which.
          meta = accepted._meta;
          # The packages the scripts run, for a package set.
          packages = pkgs: accepted._packages pkgs;
          # The scripts disko makes from the layout, for a package set:
          # `format`, `mount`, `unmount`, `destroy`, `formatMount`,
          # `destroyFormatMount`, and each of them without its
          # dependencies (`formatNoDeps` and so on).
          scripts = pkgs: accepted._scripts { inherit pkgs checked; };
        };

      # The evaluator's call, on the lib of the view being evaluated:
      # the devices option and the assertions, the framework modules of
      # the class, the selection and the configuration's module, with
      # the composition's pinned sources as the `inputs` special
      # argument. `ecosystemArgs`, which only the twin's pattern admits,
      # is merged over the call last.
      evaluate =
        args:
        { lib, manifest }:
        let
          selection = lib.caisson.integrations;
          src = ecosystemSrcOf {
            explicit = args.ecosystemSrc or null;
            inherit manifest;
          };
          rootMountPoint = if (args.rootMountPoint or null) != null then args.rootMountPoint else "/mnt";
          diskoLib = diskoLibOf { inherit lib src rootMountPoint; };
          registry = lib.caisson.modules.caisson-disko or { };
          frameworkModules = selection.frameworkModules "caisson-disko" registry;
          moduleImports = selection.moduleImportsOf "caisson-disko" { inherit lib manifest; } args;

          # The configuration's module: the module passed, else the
          # configuration registered under the configuration's name
          # (`configs/caisson-disko/<name>`), else none.
          name = manifest.name or null;
          configModule = selection.configModuleOf {
            inherit lib name;
            class = "caisson-disko";
            configModule = args.configModule or null;
          };

          moduleList = [
            (selection.caissonModule {
              key = "caisson.caisson-disko.devicesOptions";
              file = "caisson-caisson-disko:devicesOptions";
              module = devicesOptions diskoLib;
            })
            (selection.caissonModule {
              key = "caisson.caisson-disko.assertionsOptions";
              file = "caisson-caisson-disko:assertionsOptions";
              module = assertionsOptions;
            })
          ]
          ++ frameworkModules
          ++ moduleImports registry
          ++ (if configModule == null then [ ] else [ configModule ]);

          evaluated = lib.evalModules (
            {
              class = "caisson-disko";
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
          # Where disko came from, as `src` was resolved.
          ecosystems.disko = ecosystemAccountOf {
            explicit = args.ecosystemSrc or null;
            inherit manifest;
          };
          # What evalModules received: the devices option and the
          # assertions, the framework module of the class, the modules
          # selected from the registry and the configuration's module.
          # disko's type library builds the devices option; it reads
          # no module list of disko.
          modules = moduleList;
          outputs = layoutOf {
            context = "lib.caisson.caisson-disko";
            inherit (evaluated.config) assertions;
            inherit rootMountPoint;
            devices = evaluated.config.disko.devices;
            checked = args.checked or false;
          };
        };

      # A disko configuration is published as
      # `diskoConfigurations.<name>`, which disko's command reads with
      # its own evaluator: `disko.devices`, the device tree as data.
      exportsTo = {
        attrset = "diskoConfigurations";
        value = manifest: { disko.devices = manifest.outputs.serializableLayout; };
      };

      configuration =
        args:
        final.caisson.integrations.mkModuleConfiguration {
          selection = {
            class = "caisson-disko";
            inherit args;
          };
          type = "caisson-disko";
          defaultPkgs = args.defaultPkgs or null;
          inherit exportsTo;
          evaluate = evaluate args;
        };

      integration = final.caisson.integrations.mkIntegration {
        name = "caisson-disko";
        class = "caisson-disko";
        # What these return is a configuration, a function of
        # `{ name, parent }`: the parent that declares it under
        # `caisson.caisson-disko.configurations.<name>` finalizes it.
        mkConfiguration =
          {
            # The disko configuration's module: `disko.devices`, and
            # the NixOS configurations installed onto the layout under
            # `caisson.nixos.configurations`. When absent, the
            # configuration registered under the configuration's name
            # (`lib.caisson.configs.caisson-disko.<name>`), if any.
            # Further modules of the class are selected with
            # `moduleImports`, from the registry.
            configModule ? null,
            # The package sets, handed to the modules as the `pkgSets`
            # special argument.
            pkgSets ? null,
            # The package set the configurations beneath this one run
            # on: a function that receives the package sets available
            # to each, by package config name, and returns the set to
            # run on.
            defaultPkgs ? null,
            # The disko flake or source tree; resolved from the
            # composition's declarations when absent.
            ecosystemSrc ? null,
            # The selection over the caisson-disko class of the
            # registry. It replaces the default of the class, which is
            # every entry named `default` followed by what the
            # configurations above added.
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
        # What the upstream-compatible disko integration builds on, so
        # both integrations read disko the same way and make the same
        # layout product.
        extra = {
          # The disko source of a configuration: `explicit` when given,
          # else what the composition declares or pins under the name
          # `disko`, as recorded on `manifest`; refused when it is no
          # disko source.
          inherit ecosystemSrcOf;
          # Where that disko source came from, from the same arguments.
          inherit ecosystemAccountOf;
          # disko's type library from `{ lib, src, rootMountPoint }`.
          inherit diskoLibOf;
          # The module declaring `disko.devices`, for a type library.
          inherit devicesOptions;
          # The layout product of an evaluated layout.
          inherit layoutOf;
          # How a disko configuration is published: as
          # `diskoConfigurations.<name>`.
          inherit exportsTo;
        };
      };
    in
    {
      caisson = (prev.caisson or { }) // {
        caisson-disko = integration.namespace;
      };
    };

}
