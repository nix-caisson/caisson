# SPDX-License-Identifier: MIT
#
# The colmena integration: it owns the `caisson-colmena` class,
# prefixed because caisson defines it, colmena's hive format being no
# module class. A colmena configuration is a module of that class with
# `meta` (the metadata colmena's binary reads) and `nodes.<name>`, and
# the integration is not compatible with colmena's hive modules
# (`makeHive`, `defaults`, `meta.nixpkgs`). Its evaluator is the module
# system of the composed library, and the evaluator step projects the
# evaluated configuration onto the hive: the small versioned attrset
# (the hive schema) that colmena's binary reads.
#
# The configuration module receives `mkNixosConfiguration` as a module
# argument, closed over the configuration's colmena source:
# lib.caisson.nixos's composition plus colmena's public node modules
# (deploymentOptions, keyChownModule, keyServiceModule,
# assertionModule), with nixos.mkConfiguration's signature, so its
# `ecosystemSrc` is nixpkgs as for any NixOS configuration. A node is
# an ordinary NixOS configuration that also declares `deployment`; a
# consumer that exports it as `nixosConfigurations.<host>` reads it
# back from the hive, one evaluation for nixos-rebuild and colmena
# apply. Projects can contribute colmena modules through the registry
# like any other class.
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
      selection = final.caisson.integrations;

      resolveEcosystemSrc = final.caisson.integrations.resolveEcosystemSrc {
        name = "colmena";
        context = "caisson.colmena";
      };
      resolveSrc =
        explicit:
        resolveEcosystemSrc {
          inherit explicit;
          manifest = final.caisson-core.libManifest or { };
        };

      assertColmenaEcosystemSrc =
        ecosystemSrc:
        if ecosystemSrc ? lib && ecosystemSrc.lib ? makeHive && ecosystemSrc ? nixosModules then
          ecosystemSrc
        else
          throw "lib.caisson.colmena requires `ecosystemSrc.lib.makeHive` and `ecosystemSrc.nixosModules` (a colmena flake).";

      # The hive schema this integration emits. Colmena's binary asserts
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

      # colmena's public node modules, as one NixOS module.
      mkDeploymentModule = src: {
        _file = "caisson-colmena:deployment";
        imports = [
          src.nixosModules.deploymentOptions
          src.nixosModules.assertionModule
          src.nixosModules.keyChownModule
          src.nixosModules.keyServiceModule
        ];
      };

      nodeAccepted = [
        "ecosystemSrc"
        "pkgSets"
        "configModule"
        "moduleImports"
        "specialArgs"
        "system"
      ];
      nodeHints = {
        modules = "pass the host's module as `configModule`; registered nixos-class modules are selected with `moduleImports`.";
        pkgs = "pass the package set as `pkgSets.pkgs`.";
        deployment = "set `deployment.*` in the host's configModule; the node declares those options.";
      };
      checkNodeArgs = final.caisson.integrations.checkArgs {
        context = "mkNixosConfiguration (the module argument of a colmena configuration)";
        accepted = nodeAccepted;
        hints = nodeHints;
        open = "mkNixosConfigurationWithEcosystemArgs";
      };
      checkOpenNodeArgs = final.caisson.integrations.checkArgs {
        context = "mkNixosConfigurationWithEcosystemArgs (the module argument of a colmena configuration)";
        accepted = nodeAccepted ++ [ "ecosystemArgs" ];
        hints = nodeHints;
      };

      # The node constructors a colmena configuration receives, closed
      # over its colmena source: nixos.mkConfiguration over the host's
      # module plus the deployment module. Their `ecosystemSrc` is
      # nixpkgs, as for any NixOS configuration.
      mkNodeConstructors =
        src:
        let
          nodeArgsOf =
            args:
            args
            // {
              configModule = {
                _file = "caisson-colmena:node";
                imports = [
                  args.configModule
                  (mkDeploymentModule src)
                ];
              };
            };
        in
        {
          mkNixosConfiguration =
            rawArgs: final.caisson.nixos.mkConfiguration (nodeArgsOf (checkNodeArgs rawArgs));
          mkNixosConfigurationWithEcosystemArgs =
            rawArgs:
            final.caisson.nixos.mkConfigurationWithEcosystemArgs (nodeArgsOf (checkOpenNodeArgs rawArgs));
        };

      # The options of the class. `meta` declares the keys colmena's
      # binary reads (its metaOptions also declare per-node package
      # sets and special arguments, which have no meaning here: every
      # node is an evaluated configuration already).
      colmenaOptions =
        { lib, ... }:
        {
          options = {
            meta = {
              name = lib.mkOption {
                type = lib.types.str;
                default = "hive";
                description = "The name colmena's binary shows for this configuration.";
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
            nodes = lib.mkOption {
              type = lib.types.attrsOf lib.types.raw;
              default = { };
              description = "The nodes: NixOS configurations from the `mkNixosConfiguration` module argument.";
            };
          };
        };

      checkNode =
        name: node:
        if builtins.isAttrs node && node ? config && node.config ? deployment then
          node
        else
          throw ''
            lib.caisson.colmena.mkConfiguration: nodes.${name} is not a colmena node. Evaluate the host with the `mkNixosConfiguration` module argument.
          '';

      # colmena's binary selects nodes with a filter whose grammar
      # reserves two characters: a leading `@` names a tag and a `,`
      # separates entries. A node whose name uses either, or is empty,
      # could never be addressed, so the configuration refuses it
      # before any node is evaluated.
      unaddressable = name: name == "" || final.hasPrefix "@" name || final.hasInfix "," name;
      checkNodeNames =
        nodes:
        let
          bad = builtins.filter unaddressable (builtins.attrNames nodes);
        in
        if bad == [ ] then
          nodes
        else
          throw ''
            lib.caisson.colmena.mkConfiguration: colmena's node filter cannot address ${
              builtins.concatStringsSep ", " (map (n: "\"${n}\"") bad)
            }. A node name is non-empty, does not start with `@` (a tag) and contains no `,` (a separator).
          '';

      # The `evalModules` call over the class: the options of
      # the class, the framework module, the selection and the
      # configuration's module, with the node constructors as special
      # arguments.
      compose =
        {
          ecosystemSrc ? null,
          configModule,
          moduleImports ? selection.defaultModuleImports,
          specialArgs ? { },
          pkgSets ? null,
          ...
        }:
        let
          src = assertColmenaEcosystemSrc (resolveSrc ecosystemSrc);
          registry = final.caisson-core.modules.caisson-colmena or { };
          # The framework module of the class: every registered `core`, forced.
          coreModules = selection.coreModules registry;
          selectedModules = moduleImports registry;
        in
        {
          inherit src pkgSets;
          ecosystemArgs = {
            class = "caisson-colmena";
            modules = [ colmenaOptions ] ++ coreModules ++ selectedModules ++ [ configModule ];
            specialArgs =
              mkNodeConstructors src // (if pkgSets != null then { inherit pkgSets; } else { }) // specialArgs;
          };
        };

      # The evaluated configuration, projected onto the hive: the
      # attributes colmena's binary reads, under the schema version it
      # asserts.
      evaluate =
        composed: callArgs:
        let
          configuration = (final.evalModules callArgs).config;
          nodes = builtins.mapAttrs checkNode (checkNodeNames configuration.nodes);
          upstreamSchema = (composed.src.lib.makeHive { }).__schema;
        in
        if upstreamSchema != schema then
          throw "lib.caisson.colmena.mkConfiguration emits hive schema ${schema}, but this colmena expects ${upstreamSchema}."
        else
          rec {
            __schema = schema;
            inherit nodes;
            toplevel = builtins.mapAttrs (_: node: node.config.system.build.toplevel) nodes;
            deploymentConfig = builtins.mapAttrs (_: node: node.config.deployment) nodes;
            deploymentConfigSelected =
              names: final.filterAttrs (name: _: builtins.elem name names) deploymentConfig;
            evalSelected = names: final.filterAttrs (name: _: builtins.elem name names) toplevel;
            evalSelectedDrvPaths = names: builtins.mapAttrs (_: drv: drv.drvPath) (evalSelected names);
            metaConfig = final.getAttrs metaConfigKeys configuration.meta;
            introspect =
              f:
              f {
                lib = final;
                pkgs =
                  if composed.pkgSets != null && composed.pkgSets ? pkgs then
                    composed.pkgSets.pkgs
                  else
                    throw "lib.caisson.colmena: `colmena eval` needs a package set; pass `pkgSets.pkgs` to mkConfiguration.";
                inherit nodes;
              };
          };

      integration = selection.mkIntegration {
        name = "colmena";
        class = "caisson-colmena";
        # The keys of colmena's hive format, refused with a pointer to
        # the option of the colmena configuration that holds the fact.
        hints = {
          meta = "colmena's metadata is the `meta` option of the colmena configuration.";
          nodes = "the nodes are the `nodes` option of the colmena configuration.";
          defaults = "there is no module shared by every node: each node is an evaluated NixOS configuration (the `mkNixosConfiguration` module argument); select shared modules there.";
          network = "colmena's metadata is the `meta` option of the colmena configuration.";
        };
        inherit compose evaluate;
      };
    in
    contributeClasses prev integration.classes
    // {
      caisson = (prev.caisson or { }) // {
        colmena = integration.namespace;
      };
    };

}
