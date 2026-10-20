# SPDX-License-Identifier: MIT
#
# The nixidy integration: it owns the `nixidy` class, the class of
# nixidy's modules. A nixidy configuration is an environment of Argo CD
# applications, written as nixidy modules (`applications.*`,
# `nixidy.target`). It is evaluated per system, once for each system in force where it
# is declared, on the package set selected for it.
#
# caisson evaluates it with nixidy's own `mkEnv`, the function the
# nixidy flake publishes as `lib.mkEnv`. `mkEnv` runs the module system
# of the library it is given, here the composed library, and gives the
# modules nixidy's library extended by its `libOverlay`, here the
# namespaces of the composed library that nixidy's library does not
# have, such as `caisson`. nixidy returns the evaluated configuration
# and its packages but not its options, so a nixidy configuration holds
# no configurations beneath it.
#
# The outputs are nixidy's packages: `environmentPackage`, the
# rendered manifests, `activationPackage` and `bootstrapPackage`. A
# configuration is published as `nixidyEnvs.<system>.<name>`, which the
# nixidy CLI reads.
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
      context = "lib.caisson.nixidy.mkConfiguration";

      resolveEcosystemSrc = final.caisson.integrations.resolveEcosystemSrc {
        name = "nixidy";
        context = "caisson.nixidy";
      };

      # A nixidy source: the nixidy flake, which publishes `lib.mkEnv`.
      assertNixidySrc =
        ecosystemSrc:
        if builtins.isAttrs ecosystemSrc && (ecosystemSrc.lib or { }) ? mkEnv then
          ecosystemSrc
        else
          throw "${context} requires `ecosystemSrc` to be the nixidy flake (publishing lib.mkEnv).";

      evaluate =
        args:
        { lib, manifest }:
        let
          selection = lib.caisson.integrations;
          src = assertNixidySrc (resolveEcosystemSrc {
            explicit = args.ecosystemSrc or null;
            manifest = lib.caisson-core.libManifest or { };
          });

          name = manifest.name or null;
          inherit (manifest) system;
          what =
            if name != null then
              "the nixidy configuration `${name}` for ${system}"
            else
              "this nixidy configuration for ${system}";

          pkgSets = selection.pkgSetsForSystem { inherit context what; } manifest system;
          pkgs = selection.pkgSetOf { inherit context what; } manifest pkgSets;

          registry = lib.caisson.modules.nixidy or { };
          frameworkModules = selection.frameworkModules "nixidy" registry;
          moduleImports = selection.moduleImportsOf "nixidy" { inherit lib manifest; } args;

          # The configuration's module: the module passed, else the
          # configuration registered under the configuration's name
          # (`configs/nixidy/<name>`), else none.
          registered = lib.caisson.configs.nixidy or { };
          configModule =
            if (args.configModule or null) != null then
              args.configModule
            else if name != null then
              registered.${name} or null
            else
              null;

          moduleList =
            frameworkModules
            ++ moduleImports registry
            ++ (if configModule == null then [ ] else [ configModule ]);

          value = src.lib.mkEnv (
            {
              inherit pkgs lib;
              modules = moduleList;
              extraSpecialArgs = {
                inherit pkgSets;
              }
              // (if (args.specialArgs or null) != null then args.specialArgs else { });
              # The namespaces of the composed library that nixidy's
              # library does not have.
              libOverlay = _self: super: builtins.removeAttrs lib (builtins.attrNames super);
            }
            // (if (args.ecosystemArgs or null) != null then args.ecosystemArgs else { })
          );
        in
        {
          inherit value;
          # What `mkEnv` received: the modules of the composition,
          # then nixidy's module list. `mkEnv` appends nixidy's module
          # list after the modules it is given.
          modules = moduleList ++ [
            (final.caisson.integrations.ecosystemUnit {
              key = "nixidy";
              project = "nixidy";
              file = "modules/modules.nix";
            })
          ];
          outputs = {
            inherit (value) environmentPackage activationPackage bootstrapPackage;
          };
          inherit (value) config;
          options = { };
        };

      # A nixidy configuration is published as
      # `nixidyEnvs.<system>.<name>`, which the nixidy CLI reads.
      exportsTo = {
        attrset = "nixidyEnvs";
        bySystem = true;
        value = manifest: manifest.value;
      };

      configuration =
        args:
        final.caisson.integrations.mkModuleConfiguration {
          type = "nixidy";
          # A nixidy configuration is evaluated per system: it has an
          # evaluation for every system in force where it is declared.
          perSystem = true;
          defaultPkgs = args.defaultPkgs or null;
          inherit exportsTo;
          evaluate = evaluate args;
        };

      integration = final.caisson.integrations.mkIntegration {
        name = "nixidy";
        class = "nixidy";
        # A nixidy configuration that is a top, as a tool reads it: the
        # evaluation, or the evaluations by system where several are in
        # force.
        top = final.caisson.integrations.topValue;
        # What these return is a configuration, a function of
        # `{ name, parent }`: a parent that declares it under
        # `caisson.nixidy.configurations.<name>` finalizes it, and
        # `mkTopConfiguration` finalizes it at a top.
        mkConfiguration =
          {
            # The configuration's module. When absent, the configuration
            # registered under the configuration's name
            # (`lib.caisson.configs.nixidy.<name>`), if any. Further
            # modules of the class are selected with `moduleImports`,
            # from the registry.
            configModule ? null,
            # The nixidy flake; resolved from the composition's
            # declarations when absent.
            ecosystemSrc ? null,
            # The package set the configuration runs on: a function
            # that receives the package sets available where it is
            # declared, by package config name, each for the system of
            # the evaluation, and returns the set to run on. When
            # absent, the selection of the nearest configuration above,
            # and the set named `default` where none above selects.
            defaultPkgs ? null,
            # The selection over the nixidy class of the registry. It
            # replaces the default of the class, which is every entry
            # named `default` followed by what the configurations
            # above added.
            moduleImports ? null,
            # A selection added to that selection, whichever it is.
            extraModuleImports ? null,
            # Extra module arguments, merged over those the framework
            # supplies; nixidy names these `extraSpecialArgs`.
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
        nixidy = integration.namespace;
      };
    };

}
