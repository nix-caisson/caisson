# SPDX-License-Identifier: MIT
#
# The colmena integration, the upstream-compatible one: it takes a hive
# in the format colmena reads, `meta`, `defaults` and a module or list
# of modules per node, and turns each node into a caisson NixOS
# configuration declared beneath the colmena configuration. The native
# integration, caisson-colmena, takes caisson's form instead.
#
# A node is built as colmena builds it, from colmena's deployment,
# assertion and key modules, the `defaults` of the hive and the modules
# of the node, with the special arguments `name`, `nodes`,
# `meta.specialArgs` and `meta.nodeSpecialArgs.<node>`. It runs on
# `meta.nodeNixpkgs.<node>`, else `meta.nixpkgs`, else the package set
# caisson selects for it; a caller fills those from caisson's package
# sets (`meta.nixpkgs = pkgSets.default;`). As a caisson NixOS
# configuration the node also gets what caisson's NixOS evaluator gives
# any configuration: the framework modules and the default selection.
#
# `nodes` is what colmena hands its nodes: every node, evaluated again
# with type checking off, for one node to read another. A configuration
# never reads a sibling in the tree, so these evaluations are tops of
# their own, made only when a module reads them.
#
# The colmena configuration builds the hive from the NixOS
# configurations it passes up, as caisson-colmena does, and is
# published as `colmenaHive`.
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
    # The native colmena integration, whose `meta` options, hive and
    # publishing this one builds on.
    ((mkLibOverlay ../caisson-colmena) // { key = "caisson-colmena"; })
  ];

  overlay =
    final: prev:
    let
      native = final.caisson.caisson-colmena;

      # The names colmena's hive format reserves: a node may take none
      # of them.
      reservedNames = [
        "defaults"
        "network"
        "meta"
      ];

      # The keys of `meta` that say how the nodes are evaluated, which
      # this integration reads itself; the other keys are the options
      # of the class.
      evaluationMetaKeys = [
        "nixpkgs"
        "nodeNixpkgs"
        "specialArgs"
        "nodeSpecialArgs"
      ];

      # The hive as colmena reads it: an attribute set, or a function
      # called with an empty attribute set. `network` is the older name
      # of `meta`.
      hiveOf =
        rawHive:
        let
          hive =
            if builtins.isFunction rawHive || rawHive ? __functor then
              rawHive { }
            else if builtins.isAttrs rawHive then
              rawHive
            else
              throw "lib.caisson.colmena.mkConfiguration: `hive` must be an attribute set, or a function returning one.";
          meta =
            if hive ? meta && hive ? network then
              throw "lib.caisson.colmena.mkConfiguration: the hive declares both `meta` and `network`; `network` is the older name of `meta`."
            else
              hive.meta or hive.network or { };
        in
        if hive ? __schema then
          throw "lib.caisson.colmena.mkConfiguration: `hive` is an evaluated hive; pass the hive declaration, not `colmenaHive`."
        else
          {
            inherit meta;
            defaults = hive.defaults or { };
            nodes = builtins.mapAttrs (_: configs: if builtins.isList configs then configs else [ configs ]) (
              builtins.removeAttrs hive reservedNames
            );
          };

      # The package set a node runs on, from `meta.nodeNixpkgs.<node>`,
      # else `meta.nixpkgs`, or null for the set caisson selects. It must
      # be a package set already built, as colmena requires in a flake:
      # caisson hands it to NixOS whole.
      nodePkgsOf =
        hive: name:
        let
          what =
            if (hive.meta.nodeNixpkgs or { }) ? ${name} then "meta.nodeNixpkgs.${name}" else "meta.nixpkgs";
          given = (hive.meta.nodeNixpkgs or { }).${name} or (hive.meta.nixpkgs or null);
        in
        if given == null then
          null
        else if builtins.isAttrs given && given ? stdenv && !(given ? outputs) then
          given
        else
          throw ''
            lib.caisson.colmena.mkConfiguration: `${what}` must be a package set that is
            already built, such as one of caisson's package sets
            (`meta.nixpkgs = pkgSets.default;`), not a path to nixpkgs, a nixpkgs
            function or an uninitialized flake input.
          '';

      # The modules of a node, as colmena gives them: its deployment,
      # assertion and key modules, the `defaults` of the hive and the
      # modules of the node.
      nodeModules =
        src: hive: configs:
        [
          src.nixosModules.deploymentOptions
          src.nixosModules.assertionModule
          src.nixosModules.keyChownModule
          src.nixosModules.keyServiceModule
          hive.defaults
        ]
        ++ configs;

      # The arguments of the NixOS configuration of a node: its modules,
      # the special arguments colmena gives it, and the package set it
      # runs on when the hive names one.
      nodeArgs =
        src: hive: nodes: name: extraModules:
        let
          pkgs = nodePkgsOf hive name;
        in
        {
          configModule = {
            imports = nodeModules src hive hive.nodes.${name} ++ extraModules;
          };
          specialArgs = {
            inherit name nodes;
          }
          // (hive.meta.specialArgs or { })
          // ((hive.meta.nodeSpecialArgs or { }).${name} or { });
        }
        // (if pkgs == null then { } else { defaultPkgs = _pkgSets: pkgs; });

      # The module of the colmena configuration: the keys of `meta` the
      # class declares, and a NixOS configuration beneath it for each
      # node.
      hiveModule =
        src: hive:
        { lib, ... }:
        let
          # Every node again, with type checking off, for the `nodes`
          # special argument.
          uncheckedNodes = builtins.mapAttrs (
            name: _:
            lib.caisson.nixos.mkTopConfiguration (
              nodeArgs src hive uncheckedNodes name [ { _module.check = false; } ]
            )
          ) hive.nodes;
        in
        {
          meta = builtins.removeAttrs hive.meta evaluationMetaKeys;
          caisson.nixos.configurations = builtins.mapAttrs (
            name: _: lib.caisson.nixos.mkConfiguration (nodeArgs src hive uncheckedNodes name [ ])
          ) hive.nodes;
        };

      # The evaluator's call, on the lib of the view being evaluated:
      # the `meta` options, the framework modules of the class, the
      # selection and the module made from the hive, with the
      # composition's pinned sources as the `inputs` special argument.
      # `ecosystemArgs`, which only the twin's pattern admits, is merged
      # over the call last.
      evaluate =
        args:
        { lib, manifest }:
        let
          selection = lib.caisson.integrations;
          src = native.ecosystemSrcOf {
            explicit = args.ecosystemSrc or null;
            inherit manifest;
          };
          hive = hiveOf args.hive;
          registry = lib.caisson.modules.colmena or { };
          frameworkModules = selection.frameworkModules "colmena" registry;
          moduleImports = selection.moduleImportsOf "colmena" { inherit lib manifest; } args;
          moduleList = [
            native.metaOptions
          ]
          ++ frameworkModules
          ++ moduleImports registry
          ++ [ (hiveModule src hive) ];

          evaluated = lib.evalModules (
            {
              class = "colmena";
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
          # the registry and the module made from the hive. Each node is
          # a separate NixOS configuration, and the history of the node
          # records the modules NixOS received.
          modules = moduleList;
          outputs.hive = native.hiveOf {
            inherit src;
            inherit (evaluated) config;
            pkgs =
              if (args.pkgSets or null) != null && args.pkgSets ? pkgs then
                args.pkgSets.pkgs
              else
                hive.meta.nixpkgs or null;
          };
        };

      configuration =
        args:
        final.caisson.integrations.mkModuleConfiguration {
          selection = {
            class = "colmena";
            inherit args;
          };
          type = "colmena";
          defaultPkgs = args.defaultPkgs or null;
          inherit (native) exportsTo;
          evaluate = evaluate args;
        };

      integration = final.caisson.integrations.mkIntegration {
        name = "colmena";
        class = "colmena";
        # What these return is a configuration, a function of
        # `{ name, parent }`: the parent that declares it under
        # `caisson.colmena.configurations.<name>` finalizes it.
        mkConfiguration =
          {
            # The hive, in the format colmena reads: `meta`, `defaults`
            # and a module or list of modules per node. An attribute
            # set, or a function returning one.
            hive,
            # The package sets, handed to the modules of the class as
            # the `pkgSets` special argument. `colmena eval` uses
            # `pkgSets.pkgs`, else `meta.nixpkgs`.
            pkgSets ? null,
            # The package set the nodes run on when the hive names
            # none: a function that receives the package sets available
            # to each, by package config name, and returns the set to
            # run on.
            defaultPkgs ? null,
            # The colmena flake; when absent, resolved from what the
            # composition declares.
            ecosystemSrc ? null,
            # The selection over the colmena class of the registry. It
            # replaces the default of the class, which is every entry
            # named `default` followed by what the configurations above
            # added.
            moduleImports ? null,
            # A selection added to that selection, whichever it is.
            extraModuleImports ? null,
            # Extra module arguments of the colmena configuration,
            # merged over those the framework supplies.
            specialArgs ? null,
          }@args:
          configuration args;
        # The same arguments and `ecosystemArgs`, the evaluator's
        # arguments merged over the composed call last.
        mkConfigurationWithEcosystemArgs =
          {
            hive,
            pkgSets ? null,
            defaultPkgs ? null,
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
        colmena = integration.namespace;
      };
    };

}
