# SPDX-License-Identifier: MIT
#
# The microvm integration, the upstream-compatible one. A microvm
# configuration is a microvm.nix guest written as microvm.nix's users
# write one: a NixOS configuration that imports microvm.nix's guest
# module and sets its `microvm.*` options itself. It is declared inside
# the NixOS host that runs it, as
# `caisson.microvm.configurations.<name>`, and caisson's `microvm-host`
# NixOS module of the host defines `microvm.vms.<name>` from it. The
# native integration, caisson-microvm, takes caisson's form instead: a
# set of guests that share their microvm options and slots.
#
# The evaluation is the NixOS evaluation of the nixos integration:
# eval-config over the composition the nixos integration publishes
# (`lib.caisson.nixos.compose`), with microvm.nix's guest module after
# the modules of that composition. So a microvm configuration gets what
# any caisson NixOS configuration gets, the framework modules of the
# nixos class and its default selection, and its modules are modules
# of the nixos class.
#
# A microvm configuration is published as `nixosConfigurations.<name>`,
# as a NixOS configuration is.
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
    # The nixos integration, whose composition and publishing this one
    # builds on.
    ((mkLibOverlay ../nixos) // { key = "nixos"; })
    # The native microvm integration, whose resolution of the
    # microvm.nix source this one builds on.
    ((mkLibOverlay ../caisson-microvm) // { key = "caisson-microvm"; })
  ];

  overlay =
    final: prev:
    let
      nixos = final.caisson.nixos;
      native = final.caisson.caisson-microvm;

      # The evaluator's call, on the view being evaluated: eval-config
      # over the composition of the nixos class, with microvm.nix's
      # guest module, for the configuration's system. `ecosystemArgs`,
      # which only the twin's pattern admits, is merged over the call
      # last.
      evaluate =
        args: view:
        let
          common = nixos.compose { context = "lib.caisson.microvm.mkConfiguration"; } view args;
          microvmSrc = native.ecosystemSrcOf {
            explicit = args.microvmSrc or null;
            manifest = view.lib.caisson-core.libManifest or { };
          };
          guestModule = "${microvmSrc}/nixos-modules/microvm";
          callArgs = {
            modules = common.modules ++ [ guestModule ];
            inherit (common) specialArgs lib system;
          }
          // (if (args.ecosystemArgs or null) != null then args.ecosystemArgs else { });
          value = import "${common.src}/nixos/lib/eval-config.nix" callArgs;
        in
        {
          inherit value;
          # Where the module collection and microvm.nix came from.
          ecosystems = {
            nixos = common.srcAccount;
            microvm = native.ecosystemAccountOf {
              explicit = args.microvmSrc or null;
              manifest = view.lib.caisson-core.libManifest or { };
            };
          };
          # What eval-config received: NixOS' module list, the modules
          # of the composition, then microvm.nix's guest module.
          modules = [
            (final.caisson.integrations.ecosystemUnit {
              key = "nixos";
              project = "nixpkgs";
              file = "nixos/modules/module-list.nix";
            })
          ]
          ++ common.modules
          ++ [
            (final.caisson.integrations.ecosystemUnit {
              key = "microvm";
              project = "microvm";
              file = "nixos-modules/microvm";
            })
          ];
          # What `nixos-rebuild` reads from a NixOS configuration, and
          # the runner microvm.nix builds for the guest, which the host
          # installs.
          outputs = {
            toplevel = value.config.system.build.toplevel;
            runner = value.config.microvm.declaredRunner;
          };
        };

      configuration =
        args:
        final.caisson.integrations.mkModuleConfiguration {
          # The modules of a microvm configuration are modules of the
          # nixos class, selected as a NixOS configuration selects
          # them.
          selection = {
            class = "nixos";
            inherit args;
          };
          type = "microvm";
          # A guest is evaluated per system, as a NixOS configuration
          # is: for the system of its host.
          perSystem = true;
          defaultPkgs = args.defaultPkgs or null;
          inherit (nixos) exportsTo;
          # A guest is a machine of its own; a configuration with an
          # activation declared inside it checks its marker.
          activation = final.caisson.integrations.machineActivation;
          evaluate = evaluate args;
        };

      integration = final.caisson.integrations.mkIntegration {
        name = "microvm";
        class = "nixos";
        # What these return is a configuration, a function of
        # `{ name, parent }`: the NixOS host that declares it under
        # `caisson.microvm.configurations.<name>` finalizes it.
        mkConfiguration =
          {
            # The guest's module, a module of the nixos class that sets
            # the `microvm.*` options as microvm.nix's guest module
            # declares them. When absent, the configuration registered
            # under the configuration's name
            # (`lib.caisson.configs.nixos.<name>`), if any. Further
            # modules of the class are selected with `moduleImports`,
            # from the registry.
            configModule ? null,
            # The nixpkgs source tree; resolved from the composition's
            # declarations when absent.
            ecosystemSrc ? null,
            # The microvm.nix flake or source tree, as a function of the
            # tree's sources (`microvmSrc = sources: sources.<name>;`);
            # resolved from the composition's declarations under the
            # name `microvm` when absent.
            microvmSrc ? null,
            # The package set the guest runs on: a function that
            # receives the package sets available where it is
            # declared, by package config name, and returns the set to
            # run on. When absent, the selection of the nearest
            # configuration above.
            defaultPkgs ? null,
            # The selection over the nixos class of the registry. It
            # replaces the default of the class, which is every entry
            # named `default` followed by what the configurations
            # above added.
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
            ecosystemSrc ? null,
            microvmSrc ? null,
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
      # The modules of a microvm configuration are registered with
      # `lib.caisson.nixos.mkModule`, the registration form of the
      # nixos class, and every configuration registered in that class
      # is a NixOS configuration, so the namespace carries neither
      # `mkModule` nor `mkConfigurations`.
      caisson = (prev.caisson or { }) // {
        microvm = builtins.removeAttrs integration.namespace [
          "mkModule"
          "mkConfigurations"
        ];
      };
    };

}
