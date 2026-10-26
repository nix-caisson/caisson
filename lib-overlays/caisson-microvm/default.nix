# SPDX-License-Identifier: MIT
#
# The caisson-microvm integration, the native microvm.nix integration:
# it owns the `caisson-microvm` class. A caisson-microvm configuration
# holds guests that a NixOS host runs as microvm.nix virtual machines.
# It is declared inside the host as
# `caisson.caisson-microvm.configurations.<name>`, and it declares its
# guests as NixOS configurations, under `caisson.nixos.configurations`.
# Each guest sets its own `microvm.*` options in its own modules.
#
# The evaluation is caisson's own `evalModules` over the start
# options, the framework modules, the selection and the configuration's
# module. The start options, `autostart` and `restartIfChanged`, say
# how the host starts the guests. caisson's `microvm-host` NixOS module
# defines them as microvm.nix's `microvm.vms.<guest>.autostart` and
# `microvm.vms.<guest>.restartIfChanged`.
#
# The default module of the class adds caisson's `microvm-guest` NixOS
# module to the nearest NixOS configurations declared inside it, the
# guests. That module imports microvm.nix's guest module from the
# microvm.nix source this configuration resolved. caisson's
# `microvm-host` NixOS module is what a host selects to run the guests:
# it imports microvm.nix's host module and defines microvm.nix's
# `microvm.vms.<guest>` from them.
#
# A caisson-microvm configuration is not published itself. Its guests
# are published as `nixosConfigurations.<guest>`.
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
        name = "microvm";
        context = "caisson.caisson-microvm";
      };

      # A microvm.nix source: a microvm.nix flake or source tree, either
      # of which holds the guest module at `nixos-modules/microvm` and
      # the host module at `nixos-modules/host`.
      assertMicrovmEcosystemSrc =
        context: ecosystemSrc:
        let
          path = if builtins.isAttrs ecosystemSrc then ecosystemSrc.outPath or null else ecosystemSrc;
        in
        if
          path != null
          && builtins.pathExists "${path}/nixos-modules/microvm/default.nix"
          && builtins.pathExists "${path}/nixos-modules/host/default.nix"
        then
          ecosystemSrc
        else
          throw "${context} requires `ecosystemSrc` to be a microvm.nix flake or source tree (holding nixos-modules/microvm and nixos-modules/host).";

      # The microvm.nix source of a configuration: `explicit` when
      # given, else what the composition declares or pins under the
      # name `microvm`, as recorded on `manifest`.
      ecosystemSrcOf =
        { explicit, manifest }:
        assertMicrovmEcosystemSrc "lib.caisson.caisson-microvm" (resolveEcosystemSrc {
          inherit explicit manifest;
        });

      # Where that microvm.nix source came from, from the same
      # arguments, as a manifest records it under `ecosystems.microvm`.
      ecosystemAccountOf =
        { explicit, manifest }:
        final.caisson.integrations.ecosystemAccountOf ecosystem { inherit explicit manifest; };

      # The options of the class: how the host starts the guests.
      startOptions =
        { lib, ... }:
        {
          options = {
            autostart = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = ''
                Whether the host starts the guests when it boots, as
                microvm.nix's `microvm.vms.<guest>.autostart` takes it. When
                false, a guest runs only after its unit
                `microvm@<guest>.service` is started.
              '';
            };
            restartIfChanged = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = ''
                Whether switching the host to a new generation restarts a
                running guest whose configuration changed, as microvm.nix's
                `microvm.vms.<guest>.restartIfChanged` takes it.
              '';
            };
          };
        };

      # The evaluator's call, on the lib of the view being evaluated:
      # the start options, the framework modules of the class, the
      # selection and the configuration's module, with the composition's
      # pinned sources as the `inputs` special argument. `ecosystemArgs`,
      # which only the twin's pattern admits, is merged over the call
      # last.
      evaluate =
        args:
        { lib, manifest }:
        let
          selection = lib.caisson.integrations;
          src = ecosystemSrcOf {
            explicit = args.ecosystemSrc or null;
            inherit manifest;
          };
          registry = lib.caisson.modules.caisson-microvm or { };
          frameworkModules = selection.frameworkModules "caisson-microvm" registry;
          moduleImports = selection.moduleImportsOf "caisson-microvm" { inherit lib manifest; } args;

          # The configuration's module: the module passed, else the
          # configuration registered under the configuration's name
          # (`configs/caisson-microvm/<name>`), else none.
          name = manifest.name or null;
          configModule = selection.configModuleOf {
            inherit lib name;
            class = "caisson-microvm";
            configModule = args.configModule or null;
          };

          moduleList = [
            (selection.caissonModule {
              key = "caisson.caisson-microvm.startOptions";
              file = "caisson-caisson-microvm:startOptions";
              module = startOptions;
            })
          ]
          ++ frameworkModules
          ++ moduleImports registry
          ++ (if configModule == null then [ ] else [ configModule ]);

          evaluated = lib.evalModules (
            {
              class = "caisson-microvm";
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
          inherit (evaluated) config;
        in
        {
          value = evaluated;
          # Where microvm.nix came from, as `src` was resolved.
          ecosystems.microvm = ecosystemAccountOf {
            explicit = args.ecosystemSrc or null;
            inherit manifest;
          };
          # What evalModules received: the start options, the framework
          # module of the class, the modules selected from the registry
          # and the configuration's module.
          modules = moduleList;
          # What the guests and the host read. `ecosystemSrc` is the
          # microvm.nix source the guests import the guest module from.
          # `start` is how the host starts the guests.
          outputs = {
            ecosystemSrc = src;
            start = {
              inherit (config) autostart restartIfChanged;
            };
          };
        };

      configuration =
        args:
        final.caisson.integrations.mkModuleConfiguration {
          selection = {
            class = "caisson-microvm";
            inherit args;
          };
          type = "caisson-microvm";
          defaultPkgs = args.defaultPkgs or null;
          evaluate = evaluate args;
        };

      integration = final.caisson.integrations.mkIntegration {
        name = "caisson-microvm";
        class = "caisson-microvm";
        # What these return is a configuration, a function of
        # `{ name, parent }`: the NixOS host that declares it under
        # `caisson.caisson-microvm.configurations.<name>` finalizes it.
        mkConfiguration =
          {
            # The caisson-microvm configuration's module: the start
            # options and the guests under `caisson.nixos.configurations`.
            # When absent, the configuration registered under the
            # configuration's name
            # (`lib.caisson.configs.caisson-microvm.<name>`), if any.
            # Further modules of the class are selected with
            # `moduleImports`, from the registry.
            configModule ? null,
            # The package sets, handed to the modules as the `pkgSets`
            # special argument.
            pkgSets ? null,
            # The package set the guests run on: a function that
            # receives the package sets available to each, by package
            # config name, and returns the set to run on.
            defaultPkgs ? null,
            # The microvm.nix flake or source tree; resolved from the
            # composition's declarations when absent.
            ecosystemSrc ? null,
            # The selection over the caisson-microvm class of the
            # registry. It replaces the default of the class, which is
            # every entry named `default` followed by what the
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
            defaultPkgs ? null,
            ecosystemSrc ? null,
            moduleImports ? null,
            extraModuleImports ? null,
            specialArgs ? null,
            ecosystemArgs ? null,
          }@args:
          configuration args;
        # What the upstream-compatible microvm integration and the
        # host module build on, so all of them read microvm.nix the
        # same way.
        extra = {
          # The microvm.nix source of a configuration: `explicit` when
          # given, else what the composition declares or pins under the
          # name `microvm`, as recorded on `manifest`; refused when it
          # is no microvm.nix source.
          inherit ecosystemSrcOf;
          # Where that microvm.nix source came from, from the same
          # arguments.
          inherit ecosystemAccountOf;
          # The check that a value is a microvm.nix source, with the
          # name of the caller for the message.
          inherit assertMicrovmEcosystemSrc;
        };
      };
    in
    {
      caisson = (prev.caisson or { }) // {
        caisson-microvm = integration.namespace;
      };
    };

}
