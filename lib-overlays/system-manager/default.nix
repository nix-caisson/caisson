# SPDX-License-Identifier: MIT
#
# The system-manager integration: it owns the `systemManager`
# class and evaluates it with `makeSystemConfig` from the
# system-manager flake. A system-manager configuration is the system
# of a machine running another Linux distribution, evaluated per
# system, once for each system in force where it is declared, and
# published as
# `systemConfigs.<name>`, the system `system-manager switch --flake`
# reads.
#
# A system-manager configuration runs on the package set selected for
# it (`defaultPkgs`, else the set named `default`), as every other
# integration does, and on the nixpkgs the composition declares, as a
# NixOS configuration does. system-manager's flake publishes
# `makeSystemConfig` from `nix/lib.nix` called with the nixpkgs it pins;
# caisson calls the same file with the composition's nixpkgs and the
# composed library, as the NixOS integration calls
# `nixos/lib/eval-config.nix`, so the library, the NixOS modules
# system-manager imports and the evaluation all come from there.
#
# `makeSystemConfig` makes `pkgs` itself, as a `_module.args` entry that
# imports its nixpkgs, and declares `nixpkgs.pkgs` read-only with that
# argument as its default. caisson hands the selected set in as the
# `pkgs` special argument instead. The module system takes a special
# argument before `_module.args`, so the selected set is the `pkgs` of
# every module and `nixpkgs.pkgs`, and system-manager's own import is
# never evaluated. `userborn`, which `makeSystemConfig` takes from the
# userborn flake system-manager pins, is built from that same source on
# the selected set. The options `nixpkgs.overlays` and `nixpkgs.config`
# would then change nothing, so a configuration that sets them is
# refused, as one whose `nixpkgs.hostPlatform` differs from the system
# of the selected set is; package configs and package overlays are
# declared on `mkLib`. The package sets of the composition at the
# system reach the modules as the `pkgSets` argument.
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

      # The nixpkgs the evaluation runs on: the one the composition
      # declares, as for a NixOS configuration.
      resolveNixpkgsSrc = final.caisson.integrations.resolveEcosystemSrc {
        name = "nixpkgs";
        context = "caisson.system-manager";
      };

      # A system-manager source: the system-manager flake, which holds
      # `nix/lib.nix` and pins the userborn flake its modules run.
      assertSystemManagerEcosystemSrc =
        ecosystemSrc:
        if
          builtins.isAttrs ecosystemSrc
          && (ecosystemSrc.inputs or { }) ? userborn
          && builtins.pathExists "${ecosystemSrc}/nix/lib.nix"
        then
          ecosystemSrc
        else
          throw "${context} requires `ecosystemSrc` to be the system-manager flake (with its inputs, holding nix/lib.nix).";

      # system-manager imports selected NixOS modules from the nixpkgs
      # the evaluation runs on; current nixos-unstable restructured
      # nixos/modules/config/nix.nix in ways system-manager's module set
      # does not absorb. They are bridged here, where every
      # system-manager evaluation composes. Delete the bridge when
      # upstream absorbs the restructure: each half fails loudly
      # (duplicate declaration / unused disable) when its reason
      # disappears.
      compatModulesFor =
        { src, nixpkgsSrc }:
        let
          nixosNixModuleText = builtins.readFile "${nixpkgsSrc}/nixos/modules/config/nix.nix";

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
      # pattern admits, is merged over the call last; `modules`,
      # `specialArgs` and `allowUnsupportedNixpkgs` can be set or
      # replaced there. `overlays` is refused: the selected set is the
      # package set, so an overlay passed there would change nothing.
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
          # system of the evaluation, and the set it runs on: the
          # selection in force at its manifest, applied to those.
          pkgSets = selection.pkgSetsAt { inherit context what; } manifest system;
          pkgs = selection.pkgSetOf { inherit context what; } manifest pkgSets;

          nixpkgsSrc = resolveNixpkgsSrc {
            explicit = null;
            manifest = lib.caisson-core.libManifest or { };
          };

          # `makeSystemConfig` from system-manager's `nix/lib.nix`, called
          # as system-manager's flake calls it, with the composition's
          # nixpkgs and the composed library in place of its own.
          systemManagerLib = import "${src}/nix/lib.nix" {
            nixpkgs = nixpkgsSrc;
            inherit lib;
            inherit (src.inputs) userborn;
          };

          # The userborn system-manager pins, built on the selected set.
          userborn = (import "${src.inputs.userborn}/nix/packages" { inherit pkgs; }).userborn;

          ecosystemArgs = if (args.ecosystemArgs or null) != null then args.ecosystemArgs else { };

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

          # The platform of the selected set, and the refusals of what
          # the selected set makes ineffective.
          systemModule =
            { config, lib, ... }:
            {
              _file = "caisson-system-manager:system";
              nixpkgs.hostPlatform = lib.mkDefault pkgs.stdenv.hostPlatform.system;
              assertions = [
                {
                  assertion = config.nixpkgs.overlays == [ ] && config.nixpkgs.config == { };
                  message = "caisson: ${what} sets `nixpkgs.overlays` or `nixpkgs.config`, which have no effect: it runs on the package set caisson selects. Declare package configs and package overlays on `mkLib`, and select a set with `defaultPkgs`.";
                }
                {
                  assertion =
                    (
                      if builtins.isString config.nixpkgs.hostPlatform then
                        config.nixpkgs.hostPlatform
                      else
                        config.nixpkgs.hostPlatform.system or null
                    ) == pkgs.stdenv.hostPlatform.system;
                  message = "caisson: ${what} sets `nixpkgs.hostPlatform` to a platform other than that of the package set it runs on, ${pkgs.stdenv.hostPlatform.system}.";
                }
              ];
            };

          value =
            if (ecosystemArgs.overlays or [ ]) != [ ] then
              throw "${context}: ${what} passes `overlays` in `ecosystemArgs`, which have no effect: it runs on the package set caisson selects. Declare package overlays on `mkLib`."
            else
              systemManagerLib.makeSystemConfig (
                {
                  modules =
                    frameworkModules
                    ++ moduleImports registry
                    ++ (if configModule == null then [ ] else [ configModule ])
                    ++ [ systemModule ]
                    ++ compatModulesFor { inherit src nixpkgsSrc; };
                  # The module system takes a special argument before an
                  # entry of `_module.args`, so `pkgs` and `userborn`
                  # here are the ones every module receives, and the
                  # default of the read-only `nixpkgs.pkgs`.
                  specialArgs = {
                    inherit
                      lib
                      pkgSets
                      pkgs
                      userborn
                      ;
                  }
                  // (if (args.specialArgs or null) != null then args.specialArgs else { });
                }
                // ecosystemArgs
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
          defaultPkgs = args.defaultPkgs or null;
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
        # and `mkTopConfiguration` finalizes it at a top.
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
            # The package set the configuration runs on: a function
            # that receives the package sets available where it is
            # declared, by package config name, each at the system of
            # the evaluation, and returns the set to run on. When
            # absent, the selection of the nearest configuration above,
            # and the set named `default` where none above selects.
            defaultPkgs ? null,
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
        system-manager = integration.namespace;
      };
    };

}
