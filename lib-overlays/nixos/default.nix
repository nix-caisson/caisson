# SPDX-License-Identifier: MIT
#
# The nixos integration: it owns the `nixos` class and
# evaluates it with `nixos/lib/eval-config.nix` from a nixpkgs source
# tree, over the composed library. `compose` (in compose.nix) is the
# composition of the class, shared with any integration that evaluates
# the class another way.
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
      resolveEcosystemSrc = final.caisson.integrations.resolveEcosystemSrc {
        name = "nixpkgs";
        context = "caisson.nixos";
      };

      composeNixos = import ./compose.nix;

      # The composition of the class, on the view being evaluated: the
      # module list, the special arguments, the system, the package
      # sets and the resolved nixpkgs source, from the caisson
      # arguments. Every entry point here builds on it, and so does an
      # integration that evaluates the nixos class with another
      # evaluator (nixos-minimal), through `lib.caisson.nixos.compose`.
      compose =
        {
          context ? "lib.caisson.nixos.mkConfiguration",
          # Whether the evaluation carries NixOS' nixpkgs module, so
          # the package set lands on `nixpkgs.pkgs`; without it, the
          # set is the `pkgs` module argument.
          nixpkgsModule ? true,
        }:
        view: args:
        composeNixos { inherit context nixpkgsModule; } view args
        // {
          src = resolveEcosystemSrc {
            explicit = args.ecosystemSrc or null;
            manifest = view.lib.caisson-core.libManifest or { };
          };
        };

      # The evaluator's call, on the view being evaluated: eval-config
      # over the composition, at the configuration's system.
      # `baseModules` is passed where the entry point names NixOS'
      # module list itself. `ecosystemArgs`, which only the twin's
      # pattern admits, is merged over the call last.
      evaluate =
        { explicitBaseModules }:
        args: view:
        let
          common = compose { } view args;
          callArgs = {
            modules = common.modules;
            specialArgs = common.specialArgs;
            # `nixos/lib/eval-config.nix` of the nixpkgs source
            # defaults `lib` to `import ../../lib`, the library of the
            # tree it lives in. Naming it makes the composed library
            # what the evaluation runs on: its `evalModules`, its
            # merging and its type checking, and the library the
            # result publishes as `.lib`.
            lib = common.lib;
            system = common.system;
          }
          // (
            if explicitBaseModules then
              { baseModules = import "${common.src}/nixos/modules/module-list.nix"; }
            else
              { }
          )
          // (if (args.ecosystemArgs or null) != null then args.ecosystemArgs else { });
          value = import "${common.src}/nixos/lib/eval-config.nix" callArgs;
        in
        {
          inherit value;
          # What `nixos-rebuild` reads from a configuration, each a
          # reference into `config.system.build`.
          outputs = {
            toplevel = value.config.system.build.toplevel;
            vm = value.config.system.build.vm;
            vmWithBootLoader = value.config.system.build.vmWithBootLoader;
            images = value.config.system.build.images;
          };
        };

      configuration =
        variant: args:
        final.caisson.integrations.mkModuleConfiguration {
          type = "nixos";
          # A NixOS configuration is evaluated at a system: it has an
          # evaluation for every system in force where it is declared.
          perSystem = true;
          pkgSet = args.pkgSet or null;
          evaluate = evaluate variant args;
        };

      # A NixOS configuration that is a top, as a tool reads it: the
      # evaluated configuration, which is what `nixos-rebuild --file`
      # reads and what a test or the REPL evaluates with no
      # configuration above it. Where the composition has several
      # systems in force, it is the evaluated configurations by
      # system, and where it has none, the empty set: the evaluations
      # are named as anything published is (`integrations.topValue`).
      # Its name is the name the composition declares on mkLib.
      mkTopConfiguration =
        rawArgs:
        final.caisson.integrations.topValue (
          final.caisson-core.finalizeTop (final.caisson.nixos.mkConfiguration rawArgs)
        );

      integration = final.caisson.integrations.mkIntegration {
        name = "nixos";
        class = "nixos";
        # A top publishes NixOS configurations as
        # `nixosConfigurations.<name>`, each the evaluated
        # configuration, which is what `nixos-rebuild` reads.
        exportsTo = {
          attrset = "nixosConfigurations";
          value = manifest: manifest.value;
        };
        # What these return is a configuration, a function of
        # `{ name, parent }`: a parent that declares it under
        # `caisson.nixos.configurations.<name>` finalizes it, and
        # `mkTopConfiguration` finalizes it at a top. The colmena node
        # constructors take the same arguments, and
        # `lib.caisson.nixos-minimal` these plus `prefix`. The
        # configuration is evaluated at every system in force where it
        # is declared, and its package sets come from the composition,
        # through the manifest; `pkgSet` selects the set it runs on.
        mkConfiguration =
          {
            # The configuration's module. When absent, the configuration
            # registered under the configuration's name
            # (`lib.caisson-core.configs.nixos.<name>`), if any. Further
            # modules of the class are selected with `moduleImports`,
            # from the registry. The base module list belongs to the
            # entry point: mkConfiguration and mkConfigurationFull
            # evaluate with NixOS' module list,
            # lib.caisson.nixos-minimal.mkConfiguration without it.
            configModule ? null,
            # The nixpkgs source tree; resolved from the composition's
            # declarations when absent.
            ecosystemSrc ? null,
            # The package set the configuration runs on, selected from
            # the package sets available where it is declared, by
            # package config name, each at the system of the
            # evaluation (`pkgSets: pkgSets.stable`). The selection
            # holds for every configuration beneath this one that
            # selects none. When absent, the selection of the nearest
            # configuration above, and at a top the set named
            # `default`.
            pkgSet ? null,
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
          configuration { explicitBaseModules = false; } args;
        # The same arguments and `ecosystemArgs`, the evaluator's
        # arguments merged over the composed call last.
        mkConfigurationWithEcosystemArgs =
          {
            configModule ? null,
            ecosystemSrc ? null,
            pkgSet ? null,
            moduleImports ? null,
            extraModuleImports ? null,
            specialArgs ? null,
            ecosystemArgs ? null,
          }@args:
          configuration { explicitBaseModules = false; } args;
        extra = {
          inherit mkTopConfiguration;
          # eval-config with nixpkgs' module list passed explicitly as
          # `baseModules`. The signature is that of `mkConfiguration`.
          mkConfigurationFull =
            {
              configModule ? null,
              ecosystemSrc ? null,
              pkgSet ? null,
              moduleImports ? null,
              extraModuleImports ? null,
              specialArgs ? null,
            }@args:
            configuration { explicitBaseModules = true; } args;
          # The composition an alt over this class reads.
          inherit compose;
        };
      };
    in
    contributeClasses prev integration.classes
    // {
      caisson = (prev.caisson or { }) // {
        nixos = integration.namespace;
      };
    };

}
