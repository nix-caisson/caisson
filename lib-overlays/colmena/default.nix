# SPDX-License-Identifier: MIT
#
# The colmena integration. A hive is a set of NixOS configurations plus
# deployment metadata, and colmena's binary reads it through a small
# versioned attrset (the hive schema).
#
# mkNixosConfiguration evaluates a node: lib.caisson.nixos's
# composition plus colmena's public node modules (deploymentOptions,
# keyChownModule, keyServiceModule, assertionModule) from the colmena
# ecosystem source, with nixos.mkConfiguration's signature. The
# result is an ordinary NixOS configuration that also declares
# `deployment`, so `nixosConfigurations.<host>` and the hive node can
# be one evaluation.
#
# mkConfiguration evaluates the hive: a module of class `colmena` with
# `meta` (the metadata colmena's binary reads) and `nodes.<name>`
# (configurations from mkNixosConfiguration), projected onto the
# schema. Projects can contribute hive modules through the registry
# like any other class.
{ ... }:
{

  imports = [ ];

  overlay =
    final: prev:
    let
      mkHiveModule = final.caisson-core.mkModule "colmena";

      resolveEcosystemSrc = import ../resolve-ecosystem-src.nix {
        name = "colmena";
        context = "caisson.colmena";
        resolve = final.caisson-core.resolve;
      };
      resolveSrc =
        explicit:
        resolveEcosystemSrc {
          inherit explicit;
          manifest = final.caisson-core.manifest or { };
        };

      assertColmenaEcosystemSrc =
        ecosystemSrc:
        if ecosystemSrc ? lib && ecosystemSrc.lib ? makeHive && ecosystemSrc ? nixosModules then
          ecosystemSrc
        else
          throw "lib.caisson.colmena requires `ecosystemSrc.lib.makeHive` and `ecosystemSrc.nixosModules` (a colmena flake).";

      # The hive schema this integration emits. Colmena's binary asserts
      # the version; mkConfiguration asserts it against the ecosystem
      # source's own makeHive, so a colmena revision that moves the
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
      checkNodeArgs = import ../check-args.nix {
        context = "lib.caisson.colmena.mkNixosConfiguration";
        accepted = nodeAccepted;
        hints = nodeHints;
        open = "lib.caisson.colmena.mkNixosConfigurationWithEcosystemArgs";
      };
      checkOpenNodeArgs = import ../check-args.nix {
        context = "lib.caisson.colmena.mkNixosConfigurationWithEcosystemArgs";
        accepted = nodeAccepted ++ [ "ecosystemArgs" ];
        hints = nodeHints;
      };

      # A node: nixos.mkConfiguration over the host's module plus the
      # deployment module. `ecosystemSrc` is colmena's here; nixpkgs
      # resolves as nixos.mkConfiguration resolves it without an
      # explicit source (the declared `ecosystems.nixpkgs`, else the
      # input named nixpkgs).
      nodeArgsOf =
        args:
        let
          src = assertColmenaEcosystemSrc (resolveSrc (args.ecosystemSrc or null));
        in
        builtins.removeAttrs args [ "ecosystemSrc" ]
        // {
          configModule = {
            _file = "caisson-colmena:node";
            imports = [
              args.configModule
              (mkDeploymentModule src)
            ];
          };
        };
      mkNixosConfiguration =
        rawArgs: final.caisson.nixos.mkConfiguration (nodeArgsOf (checkNodeArgs rawArgs));
      mkNixosConfigurationWithEcosystemArgs =
        rawArgs:
        final.caisson.nixos.mkConfigurationWithEcosystemArgs (nodeArgsOf (checkOpenNodeArgs rawArgs));

      # The hive's options. `meta` mirrors the keys colmena's binary
      # reads (its metaOptions also declare per-node package sets and
      # special arguments, which have no meaning here: every node is an
      # evaluated configuration already).
      hiveOptions =
        { lib, ... }:
        {
          options = {
            meta = {
              name = lib.mkOption {
                type = lib.types.str;
                default = "hive";
                description = "The name of the hive.";
              };
              description = lib.mkOption {
                type = lib.types.str;
                default = "A Colmena Hive";
                description = "A short description of the hive.";
              };
              machinesFile = lib.mkOption {
                type = lib.types.nullOr lib.types.path;
                default = null;
                apply = value: if value == null then null else toString value;
                description = "The machines file passed to nix-store as `builders` when realizing this hive.";
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
              description = "The hive's nodes: NixOS configurations from lib.caisson.colmena.mkNixosConfiguration.";
            };
          };
        };

      accepted = [
        "ecosystemSrc"
        "configModule"
        "moduleImports"
        "specialArgs"
        "pkgSets"
      ];
      hints = {
        modules = "pass the hive module as `configModule`; registered colmena-class modules are selected with `moduleImports`.";
        meta = "hive metadata is the hive module's `meta`.";
        nodes = "the nodes are the hive module's `nodes`.";
        defaults = "there is no hive-wide module: every node is an evaluated NixOS configuration (mkNixosConfiguration); select shared modules there.";
        network = "hive metadata is the hive module's `meta`.";
      };
      checkArgs = import ../check-args.nix {
        context = "lib.caisson.colmena.mkConfiguration";
        inherit accepted hints;
        open = "lib.caisson.colmena.mkConfigurationWithEcosystemArgs";
      };
      checkOpenArgs = import ../check-args.nix {
        context = "lib.caisson.colmena.mkConfigurationWithEcosystemArgs";
        accepted = accepted ++ [ "ecosystemArgs" ];
        inherit hints;
      };

      checkNode =
        name: node:
        if builtins.isAttrs node && node ? config && node.config ? deployment then
          node
        else
          throw ''
            lib.caisson.colmena.mkConfiguration: nodes.${name} is not a colmena node. Evaluate the host with lib.caisson.colmena.mkNixosConfiguration.
          '';

      compose =
        {
          ecosystemSrc ? null,
          configModule,
          moduleImports ? builtins.attrValues,
          specialArgs ? { },
          pkgSets ? null,
          ...
        }:
        let
          src = assertColmenaEcosystemSrc (resolveSrc ecosystemSrc);
          selectedModules = moduleImports (final.caisson-core.modules.colmena or { });
          hive =
            (final.evalModules {
              class = "colmena";
              modules = [ hiveOptions ] ++ selectedModules ++ [ configModule ];
              specialArgs = (if pkgSets != null then { inherit pkgSets; } else { }) // specialArgs;
            }).config;
          nodes = builtins.mapAttrs checkNode hive.nodes;
          upstreamSchema = (src.lib.makeHive { }).__schema;
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
            metaConfig = final.getAttrs metaConfigKeys hive.meta;
            introspect =
              f:
              f {
                lib = final;
                pkgs =
                  if pkgSets != null && pkgSets ? pkgs then
                    pkgSets.pkgs
                  else
                    throw "lib.caisson.colmena: `colmena eval` needs a package set; pass `pkgSets.pkgs` to mkConfiguration.";
                inherit nodes;
              };
          };

      mkConfiguration = rawArgs: compose (checkArgs rawArgs);

      # The same hive, then `ecosystemArgs` merged over it verbatim: the
      # hive attrset is what colmena's binary reads, so any of its
      # attributes can be set or replaced there.
      mkConfigurationWithEcosystemArgs =
        rawArgs:
        let
          args = checkOpenArgs rawArgs;
        in
        compose args // (args.ecosystemArgs or { });
    in
    {
      caisson = (prev.caisson or { }) // {
        colmena = ((prev.caisson or { }).colmena or { }) // {
          mkModule = mkHiveModule;
          inherit
            mkConfiguration
            mkConfigurationWithEcosystemArgs
            mkNixosConfiguration
            mkNixosConfigurationWithEcosystemArgs
            ;
        };
      };
    };

}
