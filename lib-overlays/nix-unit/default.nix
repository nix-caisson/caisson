# SPDX-License-Identifier: MIT
#
# The nix-unit integration: it owns the `nixUnit` class, the class of
# the modules of a nix-unit configuration. A nix-unit configuration
# names a file of unit tests, `tests`, and the nix-unit program that
# runs them, `package` (modules/nixUnit/core). The file is a function
# that returns nix-unit's suite: an attribute set of test cases whose
# names begin with `test`, each an `expr` and its `expected` value.
#
# A nix-unit configuration is evaluated per system, once for each
# system its parent evaluates its children for. Its default check
# `unit`, of the category `unit`, runs nix-unit over the file in a
# derivation. A nix-unit configuration is published in no output
# attribute set: it leaves the flake as its check alone.
#
# nix-unit runs inside the build sandbox, where Nix can fetch nothing,
# and it evaluates the file there. The file receives `lib`, the library
# a module of the configuration that declares the nix-unit
# configuration receives, `manifest`, the manifest of that library,
# and `dependencies`, the pinned dependencies of the nix-unit
# configuration. A library cannot be handed from this evaluation to the
# evaluation in the sandbox, so the check composes the library again
# there, from its record:
#
# - Every source the library and the configuration reach, the
#   dependencies, the projects and the inputs of each, is named by its
#   store path, and a source that is a flake is evaluated again with
#   caisson's `callFlake` over its inputs (sandbox.nix). No pin reader
#   runs in the sandbox, because a pin reader calls `fetchTree`, which
#   downloads a source even when the source is already in the store.
# - Every registry entry of the library is named by the file it was
#   registered from, and the sandbox registers it again from that file
#   with the constructor that caisson-core's directory readers use.
# - The lib overlays applied are named by registry name, in the order
#   the library applied them.
#
# The record does not hold the declarations of the package configs of
# the library, which are functions, so the library composed in the
# sandbox has the names of its package configs, and a test that reads a
# package config fails.
# A registry entry that was given as a value, with no file, cannot be
# registered again, and a file outside the Nix store is not in the
# sandbox: either makes the check fail at evaluation, naming the
# entry.
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
      context = "lib.caisson.nix-unit.mkConfiguration";

      # The source information of a flake, which the sandbox gives the
      # flake again as Nix gives it to `self` of the flake.
      sourceInfoNames = [
        "rev"
        "shortRev"
        "lastModified"
        "lastModifiedDate"
        "narHash"
        "dirty"
        "dirtyRev"
        "dirtyShortRev"
        "revCount"
        "submodules"
      ];

      sourceInfoOf =
        source:
        if builtins.isAttrs source then
          final.filterAttrs (
            _: value: builtins.isString value || builtins.isInt value || builtins.isBool value
          ) (builtins.intersectAttrs (final.genAttrs sourceInfoNames (_: null)) source)
        else
          { };

      # What the sandbox reads, from the lib the configuration is
      # evaluated with and its manifest.
      sandboxDataOf =
        {
          lib,
          manifest,
          what,
          tests,
        }:
        let
          libManifest = lib.caisson-core.libManifest;
          root = libManifest.root or null;
          rootString =
            if root == null then null else builtins.unsafeDiscardStringContext (toString root.outPath);

          # A file as the sandbox names it: a string that carries the
          # store path holding the file as its context, so the
          # derivation that writes the string depends on that store path.
          # A file inside the root of the caisson top is named under the
          # store path of the root. Any other file in the store is named
          # under the store path its name begins with.
          inStore =
            entry: file:
            let
              string = toString file;
              parts = final.splitString "/" string;
              storePath = builtins.unsafeDiscardStringContext (
                builtins.concatStringsSep "/" (final.take 4 parts)
              );
            in
            if rootString != null && (string == rootString || final.hasPrefix "${rootString}/" string) then
              toString root.outPath
              + builtins.substring (builtins.stringLength rootString) (builtins.stringLength string) string
            else if final.hasPrefix "${builtins.storeDir}/" string && builtins.length parts >= 4 then
              builtins.appendContext string {
                ${storePath} = {
                  path = true;
                };
              }
            else
              throw ''
                caisson: ${what} runs nix-unit in the build sandbox, which holds only files in
                the Nix store, and ${entry} is the file `${string}`, outside the store.
                Evaluate the caisson top as a flake, whose files Nix copies to the store, or
                move the file into a source the caisson top pins.
              '';

          # A source and every source it reaches through its inputs, as
          # the nodes of a graph keyed by an identifier: the hash of the
          # store path and of the identifiers of the inputs.
          graphOf =
            entry: source:
            let
              isFlake = builtins.isAttrs source && (source._type or null) == "flake";
              outPath = inStore entry (if builtins.isAttrs source then source.outPath else source);
              inputs =
                if isFlake then
                  builtins.mapAttrs (name: graphOf "the input `${name}` of ${entry}") (source.inputs or { })
                else
                  { };
              # `builtins.toJSON` writes an attribute set that has an
              # `outPath` as that string alone, so the store path of a
              # node is its `path`.
              node = {
                path = outPath;
                flake = isFlake;
                inputs = builtins.mapAttrs (_: graph: graph.id) inputs;
                info = sourceInfoOf source;
              };
              id = builtins.hashString "sha256" (builtins.unsafeDiscardStringContext (builtins.toJSON node));
            in
            {
              inherit id;
              nodes = builtins.foldl' (nodes: graph: nodes // graph.nodes) { ${id} = node; } (
                builtins.attrValues inputs
              );
            };

          graphsOf = kind: builtins.mapAttrs (name: graphOf "the ${kind} `${name}`");
          idsOf = builtins.mapAttrs (_: graph: graph.id);
          nodesOf =
            graphs: builtins.foldl' (nodes: graph: nodes // graph.nodes) { } (builtins.attrValues graphs);

          libDependencies = graphsOf "dependency" (libManifest.dependencies or { });
          projects = graphsOf "project" (libManifest.projects or { });
          dependencies = graphsOf "dependency" (manifest.dependencies or libManifest.dependencies or { });

          # The entries of a registry that the library registered
          # itself, without those of its projects, which are named
          # `<project>/<name>` and come back with the projects.
          local = final.filterAttrs (name: _: !(final.hasInfix "/" name));

          fileOf =
            entry: attribute: value:
            if builtins.isAttrs value && value ? ${attribute} && value.${attribute} != null then
              inStore entry value.${attribute}
            else
              throw ''
                caisson: ${what} runs nix-unit in the build sandbox over the library composed
                again from its record, and ${entry} was registered as a value, with no file to
                register it from. Register it from a file, as the directory readers of
                caisson-core do.
              '';

          classEntries =
            kind: registry:
            builtins.mapAttrs (
              class: entries:
              builtins.mapAttrs (name: fileOf "the ${kind} `${kind}s.${class}.${name}`" "_file") (local entries)
            ) registry;

          libOverlays = final.filterAttrs (_: entry: (entry.project or null) == null) (
            libManifest.libOverlays or { }
          );

          # The registry names of the lib overlays the library applied,
          # in the order of the layers of its history.
          appliedKeys = builtins.map (event: event.key) (
            builtins.filter (event: event.type == "lib" && event.operation == "layer") (
              libManifest.history or [ ]
            )
          );
          libOverlayImports =
            let
              byKey = builtins.listToAttrs (
                builtins.map
                  (name: {
                    name = libManifest.libOverlays.${name}.key or name;
                    value = name;
                  })
                  (
                    builtins.filter (name: !(final.hasPrefix "caisson-core/" name)) (
                      builtins.attrNames (libManifest.libOverlays or { })
                    )
                  )
              );
            in
            final.unique (
              builtins.concatMap (key: if byKey ? ${key} then [ byKey.${key} ] else [ ]) appliedKeys
            );

          defaultEcosystemSrc = builtins.mapAttrs (
            ecosystem: name:
            if builtins.isString name then
              name
            else
              throw ''
                caisson: ${what} runs nix-unit in the build sandbox over the library composed
                again from its record, and the `defaultEcosystemSrc` of the library returns a
                ${ecosystem} source that is none of its dependencies.
              ''
          ) (libManifest.defaultEcosystemSrcNames or { });
        in
        {
          callFlake = "${../framework/call-flake.nix}";
          # The caisson-core source that composed the library: the
          # source two directories above the file of a lib overlay of
          # caisson-core, `lib-overlays/<name>` of that source.
          core =
            let
              origin = libManifest.libOverlays."caisson-core/lifecycle".origin;
            in
            inStore "the caisson-core source" (dirOf (dirOf (toString origin)));
          nodes = nodesOf libDependencies // nodesOf projects // nodesOf dependencies;
          composition = {
            dependencies = idsOf libDependencies;
            projects = idsOf projects;
            root =
              if root == null then
                null
              else
                {
                  info = sourceInfoOf root;
                  path = toString root.outPath;
                };
            name = libManifest.name or null;
            systems = libManifest.systems or null;
            inherit defaultEcosystemSrc libOverlayImports;
            libOverlays = builtins.mapAttrs (name: fileOf "the lib overlay `${name}`" "origin") libOverlays;
            modules = classEntries "module" (libManifest.modules or { });
            configs = classEntries "config" (libManifest.configs or { });
            pkgOverlays = builtins.mapAttrs (name: fileOf "the package overlay `${name}`" "origin") (
              local (libManifest.pkgOverlays or { })
            );
            pkgSets = builtins.attrNames (libManifest.pkgSets or { });
          };
          dependencies = idsOf dependencies;
          tests = inStore "the file of the tests" tests;
        };

      evaluate =
        args:
        { lib, manifest }:
        let
          selection = lib.caisson.integrations;

          name = manifest.name or null;
          inherit (manifest) system;
          what =
            if name != null then
              "the nix-unit configuration `${name}` for ${system}"
            else
              "this nix-unit configuration for ${system}";

          pkgSets = selection.pkgSetsForSystem { inherit context what; } manifest system;
          pkgs = selection.pkgSetOf { inherit context what; } manifest pkgSets;

          registry = lib.caisson.modules.nixUnit or { };
          frameworkModules = selection.frameworkModules "nixUnit" registry;
          moduleImports = selection.moduleImportsOf "nixUnit" { inherit lib manifest; } args;

          # The configuration's module: the module passed, else the
          # configuration registered under the configuration's name
          # (`configs/nixUnit/<name>`), else none.
          configModule = selection.configModuleOf {
            inherit lib name;
            class = "nixUnit";
            configModule = args.configModule or null;
          };

          # The package set the configuration runs on, and the package
          # sets for its system by the name of the package config, as
          # the module arguments `pkgs` and `pkgSets`.
          pkgsModule = selection.caissonModule {
            key = "caisson.nixUnit.pkgs";
            file = "caisson-nix-unit:pkgs";
            module = {
              _file = "caisson-nix-unit:pkgs";
              _module.args = {
                inherit pkgs pkgSets;
              };
            };
          };

          moduleList =
            frameworkModules
            ++ moduleImports registry
            ++ (if configModule == null then [ ] else [ configModule ])
            ++ [ pkgsModule ];

          # The module system hands every module the `lib` that
          # `evalModules` closed over unless `lib` is a special
          # argument. The composed library is passed as the special
          # argument `lib`, so the modules of the configuration receive
          # `lib.caisson`, and the `caisson` module of the `generic`
          # class reads it while the module system resolves `imports`.
          value = lib.evalModules (
            {
              class = "nixUnit";
              specialArgs = {
                inherit lib;
              };
              modules = moduleList;
            }
            // (if (args.ecosystemArgs or null) != null then args.ecosystemArgs else { })
          );
          inherit (value) config;

          derivationName = if name != null then "nix-unit-${name}" else "nix-unit";

          data = pkgs.writeText "${derivationName}.json" (
            builtins.toJSON (sandboxDataOf {
              inherit lib manifest what;
              inherit (config) tests;
            })
          );

          # The file nix-unit reads: the suite of the tests, called with
          # the library composed again in the sandbox.
          expression = pkgs.writeText "${derivationName}.nix" ''
            import ${./sandbox.nix} { data = ${data}; }
          '';

          # nix-unit opens a Nix store, and the build sandbox has no
          # daemon to connect to. `NIX_REMOTE` names a local store
          # under the build directory whose store directory is
          # ${builtins.storeDir}, so the store paths the expression names
          # are the paths the sandbox holds, as in nix-unit's flake-parts
          # module.
          run =
            pkgs.runCommand derivationName
              {
                nativeBuildInputs = [ config.package ];
              }
              ''
                export HOME="$(realpath .)"
                unset NIX_STORE
                export NIX_STORE_DIR=${builtins.storeDir}
                export NIX_REMOTE="$HOME/storedata"
                nix-unit --show-trace --extra-experimental-features "flakes pipe-operators" ${expression}
                touch $out
              '';
        in
        {
          inherit value;
          # What evalModules received, element by element.
          modules = moduleList;
          outputs = {
            inherit (config) tests package;
            inherit expression run;
          };
        };

      configuration =
        args:
        final.caisson.integrations.mkModuleConfiguration {
          selection = {
            class = "nixUnit";
            inherit args;
          };
          type = "nix-unit";
          # A nix-unit configuration is evaluated per system: it has an
          # evaluation result for each system its parent evaluates its
          # children for.
          perSystem = true;
          defaultPkgs = args.defaultPkgs or null;
          # A nix-unit configuration is published in no output
          # attribute set: it leaves the flake as its check alone.
          exportsTo = null;
          checks =
            { outputs, ... }:
            {
              unit = {
                derivation = outputs.run;
                category = "unit";
                description = "nix-unit runs the test cases of the file in `tests`, and every case passes.";
              };
            };
          evaluate = evaluate args;
        };

      integration = final.caisson.integrations.mkIntegration {
        name = "nix-unit";
        class = "nixUnit";
        # What these return is a configuration, a function of
        # `{ name, parent }`: a parent that declares it under
        # `caisson.nix-unit.configurations.<name>` finalizes it. A
        # nix-unit configuration is declared inside another
        # configuration, whose library its tests receive, so it has no
        # `mkTopConfiguration`.
        mkConfiguration =
          {
            # The configuration's module. When absent, the configuration
            # registered under the configuration's name
            # (`lib.caisson.configs.nixUnit.<name>`), if any. Further
            # modules of the class are selected with `moduleImports`,
            # from the registry.
            configModule ? null,
            # The package set the configuration runs on, whose `nix-unit`
            # runs the tests and whose `runCommand` builds the check: a
            # function that receives the package sets available where
            # the configuration is declared, by package config name,
            # each for the system the configuration is evaluated for,
            # and returns the set. When absent, the selection of the
            # nearest configuration above, and the set named `default`
            # where none above selects.
            defaultPkgs ? null,
            # The selection over the nixUnit class of the registry. It
            # replaces the default of the class, which is every entry
            # named `default` followed by what the configurations
            # above added.
            moduleImports ? null,
            # A selection added to that selection, whichever it is.
            extraModuleImports ? null,
          }@args:
          configuration args;
        # The same arguments and `ecosystemArgs`, the arguments merged
        # over the `evalModules` call last.
        mkConfigurationWithEcosystemArgs =
          {
            configModule ? null,
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
        nix-unit = integration.namespace;
      };
    };

}
