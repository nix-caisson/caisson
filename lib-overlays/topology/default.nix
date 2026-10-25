# SPDX-License-Identifier: MIT
#
# The topology integration: it owns the `topology` class, the class of
# nix-topology's modules. A topology configuration is the diagram of a
# network of machines: the NixOS configurations declared inside it,
# whose `topology` options nix-topology reads, and the modules of the
# class, which add nodes and networks of their own. It is evaluated per
# system, for every system in force where it is declared, on the package set
# selected for it.
#
# nix-topology evaluates its modules with `evalModules` over its
# `topology` directory, given the NixOS configurations to read as the
# option `nixosConfigurations`. caisson makes that evaluation on the
# composed library, on the selected package set extended with the
# package overlay of nix-topology, and sets `nixosConfigurations` to
# the NixOS configurations declared inside the topology configuration,
# evaluated for its system. Those NixOS configurations get the NixOS
# module of nix-topology by default, through
# `caisson.forNearestChildren`.
#
# The output is `output`, the rendered diagram. The configuration
# declared under the name `default` is published as `topology.<system>`,
# the evaluation, where nix-topology's flake module publishes it, so
# `nix build .#topology.<system>.config.output` builds the diagram.
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
      context = "lib.caisson.topology.mkConfiguration";

      resolveEcosystemSrc = final.caisson.integrations.resolveEcosystemSrc ecosystem;
      ecosystemAccountOf = final.caisson.integrations.ecosystemAccountOf ecosystem;
      ecosystem = {
        name = "nix-topology";
        context = "caisson.topology";
      };

      # A nix-topology source: the nix-topology flake or source tree,
      # which holds the topology modules, its NixOS module and its
      # package overlay.
      assertTopologySrc =
        ecosystemSrc:
        let
          path = if builtins.isAttrs ecosystemSrc then ecosystemSrc.outPath or null else ecosystemSrc;
        in
        if
          path != null
          && builtins.pathExists "${path}/topology/default.nix"
          && builtins.pathExists "${path}/nixos/module.nix"
          && builtins.pathExists "${path}/pkgs/default.nix"
        then
          ecosystemSrc
        else
          throw "${context} requires `ecosystemSrc` to be a nix-topology flake or source tree (holding topology, nixos/module.nix and pkgs/default.nix).";

      evaluate =
        args:
        { lib, manifest }:
        let
          selection = lib.caisson.integrations;
          src = assertTopologySrc (resolveEcosystemSrc {
            explicit = args.ecosystemSrc or null;
            manifest = lib.caisson-core.libManifest or { };
          });

          name = manifest.name or null;
          inherit (manifest) system;
          what =
            if name != null then
              "the topology configuration `${name}` for ${system}"
            else
              "this topology configuration for ${system}";

          pkgSets = selection.pkgSetsForSystem { inherit context what; } manifest system;
          pkgs = (selection.pkgSetOf { inherit context what; } manifest pkgSets).extend (
            import "${src}/pkgs/default.nix"
          );

          registry = lib.caisson.modules.topology or { };
          frameworkModules = selection.frameworkModules "topology" registry;
          moduleImports = selection.moduleImportsOf "topology" { inherit lib manifest; } args;

          # The configuration's module: the module passed, else the
          # configuration registered under the configuration's name
          # (`configs/topology/<name>`), else none.
          configModule = selection.configModuleOf {
            inherit lib name;
            class = "topology";
            configModule = args.configModule or null;
          };

          # The NixOS configurations declared inside, for this system, as
          # the configurations nix-topology reads. They are read in the
          # full evaluation; the childless evaluation reads none.
          machinesModule = selection.caissonModule {
            key = "caisson.topology.machines";
            file = "caisson-topology:machines";
            module =
              { config, lib, ... }:
              {
                _file = "caisson-topology:machines";
                nixosConfigurations =
                  if lib.caisson-core.evalManifest.childless then
                    { }
                  else
                    builtins.mapAttrs (_: evaluations: evaluations.${system}.value) (
                      lib.filterAttrs (_: evaluations: evaluations ? ${system}) config.caisson.nixos.configurations
                    );
                # The NixOS configurations declared inside get the NixOS
                # module of nix-topology, which declares the options
                # nix-topology reads. A NixOS configuration declared
                # inside one of them is not read and does not get it.
                caisson.forNearestChildren.extraDefaultModuleImports.nixos = _lib: [
                  (selection.caissonModule {
                    key = "caisson.topology.nixosModule";
                    file = "caisson-topology:nixosModule";
                    module = "${src}/nixos/module.nix";
                  })
                ];
              };
          };

          moduleList = [
            "${src}/topology"
            machinesModule
          ]
          ++ frameworkModules
          ++ moduleImports registry
          ++ (if configModule == null then [ ] else [ configModule ]);

          value = lib.evalModules (
            {
              class = "topology";
              prefix = [ "topology" ];
              specialArgs = {
                inherit lib pkgs pkgSets;
                modulesPath = toString "${src}/topology";
              }
              // (if (args.specialArgs or null) != null then args.specialArgs else { });
              modules = moduleList;
            }
            // (if (args.ecosystemArgs or null) != null then args.ecosystemArgs else { })
          );
        in
        {
          inherit value;
          # Where nix-topology came from, as `src` was resolved.
          ecosystems.nix-topology = ecosystemAccountOf {
            explicit = args.ecosystemSrc or null;
            manifest = lib.caisson-core.libManifest or { };
          };
          # What evalModules received: the topology module tree of
          # nix-topology, recorded as a module of the nix-topology
          # source, the module that hands it the NixOS configurations
          # declared inside, the framework module of the class, the
          # modules selected from the registry and the configuration's
          # module.
          modules = final.caisson.integrations.inEcosystem {
            name = "nix-topology";
            inherit src;
          } moduleList;
          outputs.output = value.config.output;
        };

      # The configuration named `default` is published as
      # `topology.<system>`, the evaluation.
      exportsTo = {
        attrset = "topology";
        single = true;
        bySystem = true;
        value = manifest: manifest.value;
      };

      configuration =
        args:
        final.caisson.integrations.mkModuleConfiguration {
          selection = {
            class = "topology";
            inherit args;
          };
          type = "topology";
          # A topology configuration is evaluated per system: it has an
          # evaluation for every system in force where it is declared.
          perSystem = true;
          defaultPkgs = args.defaultPkgs or null;
          inherit exportsTo;
          evaluate = evaluate args;
        };

      integration = final.caisson.integrations.mkIntegration {
        name = "topology";
        class = "topology";
        # A topology configuration that is a top, as a tool reads it:
        # the evaluation, or the evaluations by system where several
        # are in force.
        top = final.caisson.integrations.topValue;
        # What these return is a configuration, a function of
        # `{ name, parent }`: a parent that declares it under
        # `caisson.topology.configurations.<name>` finalizes it, and
        # `mkTopConfiguration` finalizes it at a top.
        mkConfiguration =
          {
            # The configuration's module: the nodes and networks of the
            # diagram, and the NixOS configurations it reads under
            # `caisson.nixos.configurations`. When absent, the
            # configuration registered under the configuration's name
            # (`lib.caisson.configs.topology.<name>`), if any. Further
            # modules of the class are selected with `moduleImports`,
            # from the registry.
            configModule ? null,
            # The nix-topology flake or source tree; resolved from the
            # composition's declarations under the name `nix-topology`
            # when absent.
            ecosystemSrc ? null,
            # The package set the configuration runs on: a function
            # that receives the package sets available where it is
            # declared, by package config name, each for the system of
            # the evaluation, and returns the set to run on. When
            # absent, the selection of the nearest configuration above,
            # and the set named `default` where none above selects.
            defaultPkgs ? null,
            # The selection over the topology class of the registry. It
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
        topology = integration.namespace;
      };
    };

}
