# SPDX-License-Identifier: MIT
#
# The treefmt integration: it owns the `treefmt` class, the class of
# treefmt-nix's modules. A treefmt configuration is the formatters of a
# tree: `programs.<name>.enable` and `settings`, as treefmt-nix writes
# them. It is evaluated per system, once for each system in force where it is declared,
# on the package set selected for it.
#
# treefmt-nix evaluates its modules with `evalModules` on the library of
# a nixpkgs. caisson evaluates them with its own `evalModules`, on the
# composed library, over the modules treefmt-nix publishes for a
# configuration embedded in another, `submodule-modules`, with `pkgs`
# set to the selected package set. Those modules need treefmt-nix's
# special arguments, which treefmt-nix publishes only inside the type
# its `submoduleWith` returns, so caisson reads them from that type.
#
# The outputs are what treefmt-nix builds: `wrapper`, treefmt with its
# configuration, which `nix fmt` runs; `configFile`, the `treefmt.toml`;
# `programs`, the formatters by name; and `check`, the function that
# takes a source tree and builds a derivation that fails when the tree
# is not formatted. The configuration declared under the name `default`
# is published as `formatter.<system>`, its wrapper, which `nix fmt`
# reads, and as `checks.<system>.treefmt`, its check over the root of
# the tree (`mkLib`'s `root`), which `nix flake check` builds.
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
      context = "lib.caisson.treefmt.mkConfiguration";

      resolveEcosystemSrc = final.caisson.integrations.resolveEcosystemSrc {
        name = "treefmt-nix";
        context = "caisson.treefmt";
      };

      # A treefmt-nix source: the treefmt-nix flake or source tree, whose
      # `default.nix` is its library.
      libraryOf =
        ecosystemSrc:
        let
          path = if builtins.isAttrs ecosystemSrc then ecosystemSrc.outPath or null else ecosystemSrc;
          library = if path != null && builtins.pathExists "${path}/default.nix" then import path else { };
        in
        if library ? submodule-modules && library ? submoduleWith then
          library
        else
          throw "${context} requires `ecosystemSrc` to be a treefmt-nix flake or source tree (whose default.nix has submodule-modules and submoduleWith).";

      evaluate =
        args:
        { lib, manifest }:
        let
          selection = lib.caisson.integrations;
          treefmt = libraryOf (resolveEcosystemSrc {
            explicit = args.ecosystemSrc or null;
            manifest = lib.caisson-core.libManifest or { };
          });

          name = manifest.name or null;
          inherit (manifest) system;
          what =
            if name != null then
              "the treefmt configuration `${name}` for ${system}"
            else
              "this treefmt configuration for ${system}";

          pkgSets = selection.pkgSetsForSystem { inherit context what; } manifest system;
          pkgs = selection.pkgSetOf { inherit context what; } manifest pkgSets;

          registry = lib.caisson.modules.treefmt or { };
          frameworkModules = selection.frameworkModules "treefmt" registry;
          moduleImports = selection.moduleImportsOf "treefmt" { inherit lib manifest; } args;

          # The configuration's module: the module passed, else the
          # configuration registered under the configuration's name
          # (`configs/treefmt/<name>`), else none.
          registered = lib.caisson.configs.treefmt or { };
          configModule =
            if (args.configModule or null) != null then
              args.configModule
            else if name != null then
              registered.${name} or null
            else
              null;

          # treefmt-nix's special arguments, from the type its
          # `submoduleWith` returns.
          upstreamSpecialArgs = (treefmt.submoduleWith lib { }).functor.payload.specialArgs;

          moduleList = [
            {
              _file = "caisson-treefmt:pkgs";
              inherit pkgs;
            }
          ]
          ++ frameworkModules
          ++ moduleImports registry
          ++ (if configModule == null then [ ] else [ configModule ]);

          value = lib.evalModules (
            {
              class = "treefmt";
              specialArgs =
                upstreamSpecialArgs
                // {
                  inherit lib pkgSets;
                }
                // (if (args.specialArgs or null) != null then args.specialArgs else { });
              modules = treefmt.submodule-modules ++ moduleList;
            }
            // (if (args.ecosystemArgs or null) != null then args.ecosystemArgs else { })
          );
          inherit (value.config) build;
        in
        {
          inherit value;
          # What evalModules received: treefmt-nix's module list, then
          # the modules of the composition.
          modules = [
            (final.caisson.integrations.ecosystemUnit {
              key = "treefmt-nix";
              project = "treefmt-nix";
              file = null;
            })
          ]
          ++ moduleList;
          outputs = {
            inherit (build)
              wrapper
              configFile
              programs
              check
              ;
          };
        };

      # Only the configuration named `default` is published: as
      # `formatter.<system>`, its wrapper, which `nix fmt` reads, and,
      # in a tree that knows its root, as `checks.<system>.treefmt`,
      # its check over that tree, which fails `nix flake check` when
      # the tree is not formatted.
      isDefault = manifest: (manifest.name or null) == "default";
      exportsTo = [
        {
          attrset = "formatter";
          single = true;
          bySystem = true;
          only = isDefault;
          value = manifest: manifest.outputs.wrapper;
        }
        {
          attrset = "checks";
          bySystem = true;
          only = manifest: isDefault manifest && (manifest.root or null) != null;
          name = _: {
            value = "treefmt";
            description = "named `treefmt`, the check of the configuration named `default`";
          };
          value = manifest: manifest.outputs.check manifest.root;
        }
      ];

      configuration =
        args:
        final.caisson.integrations.mkModuleConfiguration {
          type = "treefmt";
          # A treefmt configuration is evaluated per system: it has an
          # evaluation for every system in force where it is declared.
          perSystem = true;
          defaultPkgs = args.defaultPkgs or null;
          inherit exportsTo;
          evaluate = evaluate args;
        };

      integration = final.caisson.integrations.mkIntegration {
        name = "treefmt";
        class = "treefmt";
        # A treefmt configuration that is a top, as a tool reads it: the
        # evaluation, or the evaluations by system where several are in
        # force.
        top = final.caisson.integrations.topValue;
        # What these return is a configuration, a function of
        # `{ name, parent }`: a parent that declares it under
        # `caisson.treefmt.configurations.<name>` finalizes it, and
        # `mkTopConfiguration` finalizes it at a top.
        mkConfiguration =
          {
            # The configuration's module. When absent, the configuration
            # registered under the configuration's name
            # (`lib.caisson.configs.treefmt.<name>`), if any. Further
            # modules of the class are selected with `moduleImports`,
            # from the registry.
            configModule ? null,
            # The treefmt-nix flake or source tree; resolved from the
            # composition's declarations under the name `treefmt-nix`
            # when absent.
            ecosystemSrc ? null,
            # The package set the configuration runs on: a function
            # that receives the package sets available where it is
            # declared, by package config name, each for the system of
            # the evaluation, and returns the set to run on. When
            # absent, the selection of the nearest configuration above,
            # and the set named `default` where none above selects.
            defaultPkgs ? null,
            # The selection over the treefmt class of the registry. It
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
        treefmt = integration.namespace;
      };
    };

}
