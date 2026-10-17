# SPDX-License-Identifier: MIT
#
# The system-manager integration: it owns the `systemManager`
# class and evaluates it with `makeSystemConfig` from the
# system-manager flake. A system-manager configuration is the system
# of a machine running another Linux distribution, evaluated at every
# system in force where it is declared, and published as
# `systemConfigs.<name>`, the system `system-manager switch --flake`
# reads.
#
# system-manager builds its package set itself, from the nixpkgs its
# flake pins, at `nixpkgs.hostPlatform`, which caisson defaults to the
# system of the evaluation. The package sets of the composition at
# that system reach the modules as the `pkgSets` argument, and the
# composed library as the `lib` argument. `makeSystemConfig` runs its
# own module system on its own library, so `lib` in the modules is
# the composed library while system-manager merges and checks the
# options with its own.
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
      context = "lib.caisson.system-manager.mkConfiguration";

      resolveEcosystemSrc = final.caisson.integrations.resolveEcosystemSrc {
        name = "system-manager";
        context = "caisson.system-manager";
      };

      assertSystemManagerEcosystemSrc =
        ecosystemSrc:
        if ecosystemSrc ? lib && ecosystemSrc.lib ? makeSystemConfig then
          ecosystemSrc
        else
          throw "${context} requires `ecosystemSrc.lib.makeSystemConfig`.";

      # system-manager imports selected NixOS modules from the nixpkgs
      # input pinned in its flake; current nixos-unstable restructured
      # nixos/modules/config/nix.nix in ways system-manager's module set
      # does not absorb. They are bridged here, where every
      # system-manager evaluation composes. Delete the bridge when
      # upstream absorbs the restructure: each half fails loudly
      # (duplicate declaration / unused disable) when its reason
      # disappears.
      compatModulesFor =
        src:
        let
          smNixpkgs = src.inputs.nixpkgs;
          nixosNixModuleText = builtins.readFile "${smNixpkgs}/nixos/modules/config/nix.nix";

          # (1) That module now defines `services.displayManager.hiddenUsers`
          # (hiding nixbld users from display managers), an option nothing
          # in a system-manager eval declares, which is fatal structurally,
          # before any mkIf can discharge it. Declare the sink, following
          # system-manager's ignored-options pattern: no display
          # manager exists in a system-manager config. The sink retires
          # itself when the ignored-options file of system-manager (the
          # likely fix site) mentions the option; a fix landing anywhere
          # else surfaces as a duplicate declaration at that pin's gate.
          smIgnoredOptionsText = builtins.readFile "${src}/nix/modules/upstream/nixpkgs/default.nix";
          smDeclaresDisplayManager = final.hasInfix "displayManager" smIgnoredOptionsText;
          displayManagerSinkModule = {
            _file = "caisson-system-manager:nixpkgs-compat-sink";
            imports = [
              (
                { lib, ... }:
                {
                  options.services.displayManager.hiddenUsers = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ ];
                    description = "Compatibility sink; system-manager configs have no display manager.";
                  };
                }
              )
            ];
          };

          # (2) That module now also declares `nix.enable`/`nix.package`
          # itself, colliding with system-manager's stub declarations of
          # the same options (nix/modules/upstream/nixpkgs/nix.nix, which
          # predates them landing in the NixOS module). When the NixOS
          # module owns the options, disable the stub and re-provide the
          # config facts it carried: nix.conf must replace a foreign
          # distro's existing file, flakes stay on by default, and
          # `nix.enable` keeps the stub's off-by-default (the NixOS
          # declaration defaults it on, which would materialize nixbld
          # users on hosts whose configs did not ask for nix management).
          nixosNixOwnsDaemonOptions = final.hasInfix "services.displayManager" nixosNixModuleText;
          nixStubReplacementModule = {
            _file = "caisson-system-manager:nixpkgs-compat-nix-stub";
            disabledModules = [ "${src}/nix/modules/upstream/nixpkgs/nix.nix" ];
            imports = [
              (
                { config, lib, ... }:
                {
                  config = lib.mkMerge [
                    { nix.enable = lib.mkDefault false; }
                    (lib.mkIf config.nix.enable {
                      environment.etc."nix/nix.conf".replaceExisting = true;
                      nix.settings.experimental-features = lib.mkDefault [
                        "nix-command"
                        "flakes"
                      ];
                    })
                  ];
                }
              )
            ];
          };
        in
        final.optional (!smDeclaresDisplayManager) displayManagerSinkModule
        ++ final.optional nixosNixOwnsDaemonOptions nixStubReplacementModule;

      # The evaluator's call, on the view being evaluated:
      # `makeSystemConfig` over the framework modules, the selection,
      # the configuration's module and the bridge, at the
      # configuration's system. `ecosystemArgs`, which only the twin's
      # pattern admits, is merged over the call last; everything
      # `makeSystemConfig` takes (modules, overlays, specialArgs,
      # allowUnsupportedNixpkgs) can be set or replaced there.
      evaluate =
        args:
        { lib, manifest }:
        let
          selection = lib.caisson.integrations;
          src = assertSystemManagerEcosystemSrc (resolveEcosystemSrc {
            explicit = args.ecosystemSrc or null;
            manifest = lib.caisson-core.libManifest or { };
          });

          name = manifest.name or null;
          inherit (manifest) system;
          what =
            if name != null then
              "the system-manager configuration `${name}` at ${system}"
            else
              "this system-manager configuration at ${system}";

          # The package sets available to the configuration, each at the
          # system of the evaluation.
          pkgSets = selection.pkgSetsAt { inherit context what; } manifest system;

          registry = lib.caisson.modules.systemManager or { };
          frameworkModules = selection.frameworkModules "systemManager" registry;
          moduleImports = selection.moduleImportsOf "systemManager" { inherit lib manifest; } args;

          # The configuration's module: the module passed, else the
          # configuration registered under the configuration's name
          # (`configs/systemManager/<name>`), else none.
          registered = lib.caisson.configs.systemManager or { };
          configModule =
            if (args.configModule or null) != null then
              args.configModule
            else if name != null then
              registered.${name} or null
            else
              null;

          systemModule =
            { lib, ... }:
            {
              _file = "caisson-system-manager:system";
              nixpkgs.hostPlatform = lib.mkDefault system;
            };

          value = src.lib.makeSystemConfig (
            {
              modules =
                frameworkModules
                ++ moduleImports registry
                ++ (if configModule == null then [ ] else [ configModule ])
                ++ [ systemModule ]
                ++ compatModulesFor src;
              specialArgs = {
                inherit lib pkgSets;
              }
              // (if (args.specialArgs or null) != null then args.specialArgs else { });
            }
            // (if (args.ecosystemArgs or null) != null then args.ecosystemArgs else { })
          );
        in
        {
          inherit value;
          # What `system-manager switch` activates: the system itself.
          outputs.toplevel = value;
        };

      # A system-manager configuration is published as
      # `systemConfigs.<name>`, which `system-manager switch --flake`
      # reads, with `default` as the name it reads when none is given.
      exportsTo = {
        attrset = "systemConfigs";
        value = manifest: manifest.value;
      };

      configuration =
        args:
        final.caisson.integrations.mkModuleConfiguration {
          type = "system-manager";
          # A system-manager configuration is evaluated per system: it
          # has an evaluation for every system in force where it is
          # declared.
          perSystem = true;
          defaultPkgs = null;
          inherit exportsTo;
          # A system-manager configuration is activated on a machine;
          # the configurations with an activation declared inside it
          # check its marker.
          activation = final.caisson.integrations.machineActivation;
          evaluate = evaluate args;
        };

      integration = final.caisson.integrations.mkIntegration {
        name = "system-manager";
        class = "systemManager";
        # A system-manager configuration that is a top, as a tool reads
        # it: the system, or the systems by system where several are in
        # force.
        top = final.caisson.integrations.topValue;
        # What these return is a configuration, a function of
        # `{ name, parent }`: a parent that declares it under
        # `caisson.system-manager.configurations.<name>` finalizes it,
        # and `mkTopConfiguration` finalizes it at a top. system-manager
        # builds its own package set, so there is no `defaultPkgs`.
        mkConfiguration =
          {
            # The configuration's module. When absent, the configuration
            # registered under the configuration's name
            # (`lib.caisson.configs.systemManager.<name>`), if any.
            # Further modules of the class are selected with
            # `moduleImports`, from the registry.
            configModule ? null,
            # The system-manager flake; resolved from the composition's
            # declarations when absent.
            ecosystemSrc ? null,
            # The selection over the systemManager class of the
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
            ecosystemSrc ? null,
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
        system-manager = integration.namespace;
      };
    };

}
