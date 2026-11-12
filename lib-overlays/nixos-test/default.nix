# SPDX-License-Identifier: MIT
#
# The nixos-test integration: it owns the `nixosTest` class, the class
# of the test modules of the NixOS test framework, and evaluates it
# with `evalTest` from `nixos/lib` of a nixpkgs source tree. A test
# such as `nixos/tests/login.nix` of nixpkgs is a module of this
# class: it names the test, declares its nodes under `nodes.<name>`
# and gives the Python test script as `testScript`.
#
# A test is evaluated per system, once for each system its parent
# evaluates its children for. The package set the selection of the
# test picks for that system is the `hostPkgs` of the test framework,
# the set the test driver and the VMs run with, and its `pkgsLinux` is
# `node.pkgs`, the set the nodes run on. `pkgs.testers.runNixOSTest`
# of nixpkgs sets the two options the same way, so a test declared
# through this integration builds the same derivation as that call
# with the same test module.
#
# The test framework evaluates the nodes of a test itself:
# `nixos/lib/testing/nodes.nix` calls `nixos/lib/eval-config.nix` over
# the base modules of the framework and the definitions of
# `nodes.<name>`. The nodes are therefore no NixOS configurations of
# caisson. The manifest of the test records the modules each node is
# given as `declaration` events of the test that carry the name of the
# node.
#
# A test leaves the flake only as a check: its default check `test` is
# the run of the test driver, of the category `vm`, and no output
# attribute set publishes the test. A test declared inside a NixOS
# configuration reads the result of the childless evaluation of that
# NixOS configuration as `nearest.nixos` of its manifest,
# `lib.caisson-core.evalManifest.nearest.nixos.value.config`, as a
# home-manager configuration declared there does.
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
      context = "lib.caisson.nixos-test.mkConfiguration";

      # The test framework lives in `nixos/lib/testing` of the source of
      # the NixOS module collection, the `nixos` key of the
      # composition, as the nixos integration resolves it.
      resolveEcosystemSrc = final.caisson.integrations.resolveEcosystemSrc ecosystem;
      ecosystemAccountOf = final.caisson.integrations.ecosystemAccountOf ecosystem;
      ecosystem = {
        name = "nixos";
        context = "caisson.nixos-test";
      };

      # The evaluator's call, on the lib and manifest the test is
      # evaluated with: `evalTest` over the framework modules of the
      # class, the selection and the configuration's module, with the
      # package set of the test. `evalTest` takes a single test module,
      # and `ecosystemArgs`, which only the pattern of the
      # `WithEcosystemArgs` variant admits, is merged over the
      # attributes of that module last, so `hostPkgs`, `node` and
      # `imports` can be set or replaced there.
      evaluate =
        args:
        { lib, manifest }:
        let
          selection = lib.caisson.integrations;
          src = resolveEcosystemSrc {
            explicit = args.ecosystemSrc or null;
            manifest = lib.caisson-core.libManifest or { };
          };

          name = manifest.name or null;
          inherit (manifest) system;
          what =
            if name != null then "the NixOS test `${name}` for ${system}" else "this NixOS test for ${system}";

          pkgSets = selection.pkgSetsForSystem { inherit context what; } manifest system;
          # The set the test driver and the VMs run with.
          pkgs = selection.pkgSetOf { inherit context what; } manifest pkgSets;

          registry = lib.caisson.modules.nixosTest or { };
          frameworkModules = selection.frameworkModules "nixosTest" registry;
          moduleImports = selection.moduleImportsOf "nixosTest" { inherit lib manifest; } args;

          # The configuration's module: the module passed, else the
          # configuration registered under the name of the test
          # (`configs/nixosTest/<name>`), else none.
          configModule = selection.configModuleOf {
            inherit lib name;
            class = "nixosTest";
            configModule = args.configModule or null;
          };

          # The test framework names every derivation it builds after
          # the `name` of the test, which a test module usually sets.
          # A test declared under a name is named by it unless a
          # module of the test names it otherwise.
          nameModule = selection.caissonModule {
            key = "caisson.nixosTest.name";
            file = "caisson-nixos-test:name";
            module = {
              _file = "caisson-nixos-test:name";
              name = lib.mkDefault name;
            };
          };

          # The package sets for the system of the test, by the name of
          # the package config, as the module argument `pkgSets`.
          # `evalTest` takes no special arguments, so the argument is a
          # module argument.
          pkgSetsModule = selection.caissonModule {
            key = "caisson.nixosTest.pkgSets";
            file = "caisson-nixos-test:pkgSets";
            module = {
              _file = "caisson-nixos-test:pkgSets";
              _module.args.pkgSets = pkgSets;
            };
          };

          moduleList =
            frameworkModules
            ++ moduleImports registry
            ++ (if configModule == null then [ ] else [ configModule ])
            ++ (if name == null then [ ] else [ nameModule ])
            ++ [ pkgSetsModule ];

          # The library the test and its nodes are evaluated with.
          # `evalTest` calls `evalModules` of the library it is given
          # with no special arguments. The module system then hands
          # every module the library that `lib/modules.nix` closed
          # over, which is the fixpoint of nixpkgs and has none of what
          # the composition contributed, `lib.caisson` among it.
          # Applying `extend` to the composed library re-ties the
          # library of nixpkgs over a new fixpoint, and this library
          # takes its `modules`, `types` and `evalModules` from that
          # re-tied copy. Every module of the test receives this
          # library, with `lib.caisson` and the manifest of the test.
          # `nixos/lib/testing/nodes.nix` evaluates the nodes with the
          # library of the test, so the nodes receive it too.
          testLib = lib.extend (
            _self: super:
            lib
            // {
              inherit (super) modules types evalModules;
            }
          );

          # The test module `evalTest` receives. `pkgs.testers.runNixOSTest`
          # sets `hostPkgs` to the package set it belongs to and
          # `node.pkgs` to the `pkgsLinux` of that set, which is the set
          # itself on Linux and the set for the Linux system of the same
          # CPU on macOS.
          testModule = {
            imports = moduleList;
            hostPkgs = pkgs;
            node.pkgs = pkgs.pkgsLinux;
          }
          // (if (args.ecosystemArgs or null) != null then args.ecosystemArgs else { });

          value = (import "${src}/nixos/lib" { lib = testLib; }).evalTest testModule;

          # The modules each node is given, as the definitions of
          # `nodes` in the modules of the test hold them, by the name of
          # the node. A module given as a value carries the file of the
          # definition, so its `declaration` event names that file. The
          # module system names the file of a definition in a module
          # that was given as a value with no file `lib.unknownModule`,
          # the string `<unknown-file>`, and such a module carries no
          # file.
          nodeModules = builtins.foldl' (
            byNode: definition:
            byNode
            // builtins.mapAttrs (
              node: module:
              (byNode.${node} or [ ])
              ++ [
                (
                  if builtins.isPath module || builtins.isString module then
                    module
                  else if builtins.isAttrs module && module ? key then
                    module
                  else if definition.file == lib.unknownModule then
                    module
                  else
                    {
                      _file = definition.file;
                      imports = [ module ];
                    }
                )
              ]
            ) definition.value
          ) { } value.options.nodes.definitionsWithLocations;
        in
        {
          inherit value;
          # Where the test framework came from, as `src` was resolved.
          ecosystems.nixos = ecosystemAccountOf {
            explicit = args.ecosystemSrc or null;
            manifest = lib.caisson-core.libManifest or { };
          };
          # What `evalTest` received: the module list of the test
          # framework, then the modules of the composition.
          modules = [
            (final.caisson.integrations.ecosystemUnit {
              key = "nixos-test";
              project = "nixpkgs";
              file = "nixos/lib/testing/default.nix";
            })
          ]
          ++ moduleList;
          # The modules of each node, as `declaration` events of the
          # test that carry the name of the node. A module from the
          # registry or a file is keyed as any module of a
          # configuration is. A module given as a value is keyed by
          # where the test declares it, `nodes.<node>/<index>`, with
          # its index among the modules of the node.
          events = builtins.concatMap (
            node:
            builtins.map
              (
                event:
                event
                // {
                  inherit node;
                }
                // (
                  if lib.hasPrefix "inline/" event.key then
                    { key = "nodes.${node}/${lib.removePrefix "inline/" event.key}"; }
                  else
                    { }
                )
              )
              (
                final.caisson.integrations.declarationEventsOf {
                  inherit lib;
                  modules = nodeModules.${node};
                }
              )
          ) (builtins.attrNames nodeModules);
          # The derivation that runs the test, the test driver, and the
          # driver that runs the test interactively, as the test
          # framework builds them.
          outputs = {
            test = value.config.test;
            driver = value.config.driver;
            driverInteractive = value.config.interactive.driver;
          };
        };

      configuration =
        args:
        final.caisson.integrations.mkModuleConfiguration {
          selection = {
            class = "nixosTest";
            inherit args;
          };
          type = "nixos-test";
          # A test is evaluated per system: it has an evaluation result
          # for each system its parent evaluates its children for.
          perSystem = true;
          defaultPkgs = args.defaultPkgs or null;
          # A test is published in no output attribute set: it leaves
          # the flake as its check alone.
          exportsTo = null;
          checks =
            { outputs, ... }:
            {
              test = {
                derivation = outputs.test;
                category = "vm";
                description = "The test driver starts the nodes of the test and the test script passes.";
              };
            };
          evaluate = evaluate args;
        };

      integration = final.caisson.integrations.mkIntegration {
        name = "nixos-test";
        class = "nixosTest";
        # What these return is a configuration, a function of
        # `{ name, parent }`: a parent that declares it under
        # `caisson.nixos-test.configurations.<name>` finalizes it. A
        # test is declared inside another configuration, so it has no
        # `mkTopConfiguration`.
        mkConfiguration =
          {
            # The test module. When absent, the configuration registered
            # under the name of the test
            # (`lib.caisson.configs.nixosTest.<name>`), if any. Further
            # modules of the class are selected with `moduleImports`,
            # from the registry.
            configModule ? null,
            # The nixpkgs source tree that holds the test framework in
            # `nixos/lib/testing`; resolved from the declarations of the
            # composition for `nixos` when absent.
            ecosystemSrc ? null,
            # The package set the test driver and the VMs run with: a
            # function that receives the package sets available where
            # the test is declared, by package config name, each for
            # the system the test is evaluated for, and returns the set.
            # When absent, the selection of the nearest configuration
            # above, which inside a NixOS configuration is the set of
            # that NixOS configuration, and the set named `default`
            # where none above selects.
            defaultPkgs ? null,
            # The selection over the nixosTest class of the registry. It
            # replaces the default of the class, which is every entry
            # named `default` followed by what the configurations
            # above added.
            moduleImports ? null,
            # A selection added to that selection, whichever it is.
            extraModuleImports ? null,
          }@args:
          configuration args;
        # The same arguments and `ecosystemArgs`, attributes merged over
        # the test module `evalTest` receives, last.
        mkConfigurationWithEcosystemArgs =
          {
            configModule ? null,
            ecosystemSrc ? null,
            defaultPkgs ? null,
            moduleImports ? null,
            extraModuleImports ? null,
            ecosystemArgs ? null,
          }@args:
          configuration args;
      };
    in
    {
      caisson = (prev.caisson or { }) // {
        nixos-test = integration.namespace;
      };
    };

}
