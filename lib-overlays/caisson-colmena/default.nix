# SPDX-License-Identifier: MIT
#
# The caisson-colmena integration, the native colmena integration: it
# owns the `caisson-colmena` class, prefixed because caisson defines
# it, colmena's hive format being no module class. A colmena
# configuration is a module of that class with
# `meta`, the metadata colmena's command reads. It declares the
# machines colmena deploys the way any configuration declares NixOS
# configurations, under `caisson.nixos.configurations.<name>`.
#
# The nodes are the NixOS configurations passed up from beneath the
# colmena configuration, each under the name it is published under.
# The default module of the class adds caisson's `colmena-deployment`
# NixOS module to those configurations, which declares colmena's
# `deployment` options; the integration reads `deployment` back from
# each node and builds the hive: the small versioned attribute set
# (the hive schema) that colmena's command reads. The integration is
# not compatible with colmena's hive modules (`makeHive`, `defaults`,
# `meta.nixpkgs`): every node is an evaluated NixOS configuration.
#
# A colmena configuration is published as `colmenaHive`, an output that
# holds a single value, so the configuration declared under the name
# `default` fills it. The nodes are published as well, as the NixOS
# configurations they are, so `nixos-rebuild` and `colmena apply` build
# the same machine.
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

      resolveEcosystemSrc = final.caisson.integrations.resolveEcosystemSrc {
        name = "colmena";
        context = "caisson.caisson-colmena";
      };

      assertColmenaEcosystemSrc =
        ecosystemSrc:
        if ecosystemSrc ? lib && ecosystemSrc.lib ? makeHive && ecosystemSrc ? nixosModules then
          ecosystemSrc
        else
          throw "lib.caisson.caisson-colmena requires `ecosystemSrc.lib.makeHive` and `ecosystemSrc.nixosModules` (a colmena flake).";

      # The hive schema this integration emits. Colmena's command asserts
      # the version; the evaluator step asserts it against the makeHive
      # of the ecosystem source, so a colmena revision that moves the
      # schema fails loudly at evaluation rather than at deploy time.
      schema = "v0.5";
      metaConfigKeys = [
        "name"
        "description"
        "machinesFile"
        "allowApplyAll"
      ];

      # The options of the class. `meta` declares the keys colmena's
      # command reads (its metaOptions also declare per-node package
      # sets and special arguments, which have no meaning here: every
      # node is an evaluated configuration already).
      colmenaOptions =
        { lib, ... }:
        {
          options.meta = {
            name = lib.mkOption {
              type = lib.types.str;
              default = "hive";
              description = "The name colmena's command shows for this configuration.";
            };
            description = lib.mkOption {
              type = lib.types.str;
              default = "A Colmena Hive";
              description = "A short description of the configuration.";
            };
            machinesFile = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              apply = value: if value == null then null else toString value;
              description = "The machines file passed to nix-store as `builders` when realizing the nodes.";
            };
            allowApplyAll = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether `colmena apply` without a node filter is allowed.";
            };
          };
        };

      # colmena's command selects nodes with a filter whose grammar
      # reserves characters: a leading `@` names a tag and a `,`
      # separates entries. A node whose name uses either, or is empty,
      # could never be addressed, so the hive refuses it.
      unaddressable = name: name == "" || final.hasPrefix "@" name || final.hasInfix "," name;

      # A machine colmena deploys is one evaluation. A NixOS
      # configuration with several systems in force is evaluated per
      # system, and publishing would make each evaluation a node. The
      # machines evaluated more than once, each with its name and its
      # systems: the NixOS entries grouped by their path without the
      # system segments, where a group has more than one entry.
      evaluatedMoreThanOnce =
        entries:
        let
          machines = builtins.filter (entry: entry.attrset == "nixosConfigurations") entries;
          nameOf =
            entry:
            final.caisson.integrations.displayName (
              builtins.map (segment: segment.name) (
                builtins.filter (segment: segment.type != "system") entry.path
              )
            );
          grouped = builtins.groupBy nameOf machines;
        in
        final.mapAttrsToList (name: group: {
          inherit name;
          systems = builtins.map (entry: entry.system) group;
        }) (final.filterAttrs (_: group: builtins.length group > 1) grouped);

      # The nodes, by the name each is published under: the NixOS
      # configurations among the entries the colmena configuration
      # passes up. A node is refused when it has more than one
      # evaluation, when colmena could not select it, and when it does
      # not declare the `deployment` options colmena reads.
      nodesOf =
        entries:
        let
          repeated = evaluatedMoreThanOnce entries;
          published = (final.caisson.integrations.publish entries).nixosConfigurations or { };
          bad = builtins.filter unaddressable (builtins.attrNames published);
          checked =
            name: node:
            if node ? config && node.config ? deployment then
              node
            else
              throw ''
                lib.caisson.caisson-colmena: the node `${name}` declares no `deployment` options,
                which colmena reads. A NixOS configuration declared inside a colmena
                configuration gets them from caisson's `colmena-deployment` module by
                default; one that passes `moduleImports` lists that module itself.
              '';
        in
        if repeated != [ ] then
          throw ''
            lib.caisson.caisson-colmena: a node is one evaluation of a NixOS configuration,
            and these NixOS configurations are evaluated per system, for more than one system:
            ${builtins.concatStringsSep "\n" (
              builtins.map (
                machine: "  `${machine.name}`, for ${builtins.concatStringsSep ", " machine.systems}"
              ) repeated
            )}
            Declare each machine where a single system is in force.
          ''
        else if bad == [ ] then
          builtins.mapAttrs checked published
        else
          throw ''
            lib.caisson.caisson-colmena: colmena's node filter cannot address ${
              builtins.concatStringsSep ", " (map (n: "\"${n}\"") bad)
            }. A node name is non-empty, does not start with `@` (a tag) and contains no `,` (a separator).
          '';

      # The hive: the attributes colmena's command reads, under the
      # schema version it asserts. A `targetHost` left at `null` is the
      # node's name.
      hiveOf =
        {
          src,
          config,
          pkgs,
        }:
        let
          nodes = nodesOf config.caisson.exports.configurations;
          upstreamSchema = (src.lib.makeHive { }).__schema;
        in
        if upstreamSchema != schema then
          throw "lib.caisson.caisson-colmena emits hive schema ${schema}, but this colmena expects ${upstreamSchema}."
        else
          rec {
            __schema = schema;
            inherit nodes;
            toplevel = builtins.mapAttrs (_: node: node.config.system.build.toplevel) nodes;
            deploymentConfig = builtins.mapAttrs (
              name: node:
              node.config.deployment
              // {
                targetHost =
                  if node.config.deployment.targetHost == null then name else node.config.deployment.targetHost;
              }
            ) nodes;
            deploymentConfigSelected =
              names: final.filterAttrs (name: _: builtins.elem name names) deploymentConfig;
            evalSelected = names: final.filterAttrs (name: _: builtins.elem name names) toplevel;
            evalSelectedDrvPaths = names: builtins.mapAttrs (_: drv: drv.drvPath) (evalSelected names);
            metaConfig = final.getAttrs metaConfigKeys config.meta;
            introspect =
              f:
              f {
                lib = final;
                pkgs =
                  if pkgs != null then
                    pkgs
                  else
                    throw "lib.caisson.caisson-colmena: `colmena eval` needs a package set; pass `pkgSets.pkgs` to mkConfiguration.";
                inherit nodes;
              };
          };

      # The evaluator's call, on the lib of the view being evaluated:
      # the options of the class, the framework modules of the class, the
      # selection and the configuration's module, with the composition's
      # pinned sources as the `inputs` special argument. `ecosystemArgs`,
      # which only the twin's pattern admits, is merged over the call
      # last.
      evaluate =
        args:
        { lib, manifest }:
        let
          selection = lib.caisson.integrations;
          src = assertColmenaEcosystemSrc (resolveEcosystemSrc {
            explicit = args.ecosystemSrc or null;
            inherit manifest;
          });
          registry = lib.caisson.modules.caisson-colmena or { };
          frameworkModules = selection.frameworkModules "caisson-colmena" registry;
          moduleImports = selection.moduleImportsOf "caisson-colmena" { inherit lib manifest; } args;

          # The configuration's module: the module passed, else the
          # configuration registered under the configuration's name
          # (`configs/caisson-colmena/<name>`), else none.
          name = manifest.name or null;
          registered = lib.caisson.configs.caisson-colmena or { };
          configModule =
            if (args.configModule or null) != null then
              args.configModule
            else if name != null then
              registered.${name} or null
            else
              null;

          moduleList = [
            colmenaOptions
          ]
          ++ frameworkModules
          ++ moduleImports registry
          ++ (if configModule == null then [ ] else [ configModule ]);

          evaluated = lib.evalModules (
            {
              class = "caisson-colmena";
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
          # What evalModules received: the options of the class, the
          # framework module of the class, the modules selected from
          # the registry and the configuration's module. Each node is a
          # separate NixOS configuration, and the history of the node
          # records the modules NixOS received.
          modules = moduleList;
          outputs.hive = hiveOf {
            inherit src;
            inherit (evaluated) config;
            pkgs = (args.pkgSets or { }).pkgs or null;
          };
        };

      # A colmena configuration is published as `colmenaHive`, an output
      # that holds a single value: the hive.
      exportsTo = {
        attrset = "colmenaHive";
        single = true;
        value = manifest: manifest.outputs.hive;
      };

      configuration =
        args:
        final.caisson.integrations.mkModuleConfiguration {
          type = "caisson-colmena";
          defaultPkgs = args.defaultPkgs or null;
          inherit exportsTo;
          evaluate = evaluate args;
        };

      integration = final.caisson.integrations.mkIntegration {
        name = "caisson-colmena";
        class = "caisson-colmena";
        # What these return is a configuration, a function of
        # `{ name, parent }`: the parent that declares it under
        # `caisson.caisson-colmena.configurations.<name>` finalizes it.
        mkConfiguration =
          {
            # The colmena configuration's module: `meta`, and the
            # machines under `caisson.nixos.configurations`. When
            # absent, the configuration registered under the
            # configuration's name
            # (`lib.caisson.configs.caisson-colmena.<name>`), if any.
            # Further modules of the class are selected with
            # `moduleImports`, from the registry.
            configModule ? null,
            # The package sets, handed to the modules as the `pkgSets`
            # special argument; `colmena eval` needs `pkgSets.pkgs`
            # and reports the miss.
            pkgSets ? null,
            # The package set the configurations beneath this one run
            # on: a function that receives the package sets available
            # to each, by package config name, and returns the set to
            # run on.
            defaultPkgs ? null,
            # The colmena flake; resolved from the composition's
            # declarations when absent.
            ecosystemSrc ? null,
            # The selection over the caisson-colmena class of the
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
        # What the upstream-compatible colmena integration builds on, so
        # both integrations read colmena the same way and build the same
        # hive from what a colmena configuration passes up.
        extra = {
          # The module declaring `meta`, the keys colmena's command reads.
          metaOptions = colmenaOptions;
          # The hive of an evaluated colmena configuration, from its
          # `config`, the colmena source and the package set of
          # `colmena eval`.
          inherit hiveOf;
          # How a colmena configuration is published: as `colmenaHive`.
          inherit exportsTo;
          # The colmena source of a configuration: `explicit` when given,
          # else what the composition declares or pins under the name
          # `colmena`, as recorded on `manifest`; refused when it is no
          # colmena flake.
          ecosystemSrcOf =
            { explicit, manifest }:
            assertColmenaEcosystemSrc (resolveEcosystemSrc {
              inherit explicit manifest;
            });
        };
      };
    in
    {
      caisson = (prev.caisson or { }) // {
        caisson-colmena = integration.namespace;
      };
    };

}
