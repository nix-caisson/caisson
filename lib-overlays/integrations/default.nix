# SPDX-License-Identifier: MIT
#
# What an integration is written from: the functions every integration
# overlay shares, under `lib.caisson.integrations`. Each integration
# imports this overlay by key, so composing any of them composes
# this, and reads the functions through `final`. `mkIntegration` and
# `mkAltIntegration` generate an integration from its declaration
# (design section 8) out of these pieces.
#
#   mkEvaluation         the evaluation an entry point performs: every
#                        integration takes exactly the caisson-shaped
#                        arguments (configModule, moduleImports,
#                        specialArgs, pkgSets, ecosystemSrc, and the
#                        few of its ecosystem) and composes the evaluator's
#                        call from them. Nothing else is forwarded: an
#                        evaluator argument handed in directly would be
#                        silently overwritten, silently dropped, or
#                        surface as a conflict deep inside the
#                        evaluator. The `...WithEcosystemArgs` variant of
#                        each entry point is the way to the evaluator's
#                        full surface: the same arguments plus
#                        `ecosystemArgs`, merged over the composed call
#                        verbatim, last.
#
#                        The signature is the pattern of the entry
#                        point. An entry point is a function of an
#                        attribute set pattern with no `...`, so Nix
#                        matches the call against the pattern before any
#                        of the body exists: a missing or unexpected
#                        argument is Nix's error, named after the
#                        entry point and raised at the call site, with
#                        no frame of the composition or the evaluator
#                        above it. The pattern names every argument the
#                        entry point takes and marks the optional arguments
#                        with `? null`; the composition supplies the
#                        value of an omitted argument, so the pattern
#                        binds `@args` and hands the call on as it came.
#                        `builtins.functionArgs` reads the signature
#                        back as data.
#   resolveEcosystemSrc  the layered ecosystem-source resolution:
#                        caisson-core's `resolve` (the explicit
#                        argument, then the composition's declared
#                        `defaultEcosystemSrc.<name>`, then the pinned
#                        source with exactly the declared name), with
#                        the miss interpreted here, where the
#                        integration knows what to say; the resolver
#                        itself never formats a message, because a miss
#                        is the plain value null. The declarations and
#                        dependencies are read from the manifest
#                        of the composition; a manifest-less
#                        composition resolves only the explicit
#                        argument.
#   coreModules          the selections every integration draws
#   defaultModuleImports from the registry of its class, by entry name:
#                        every entry named `core` (the local `core` and
#                        a consumed project's `<project>/core`) is the
#                        framework module of the class, forced into
#                        the modules of every configuration of the
#                        class before anything the configuration
#                        selects; every entry named `default`,
#                        likewise, is the default default, what
#                        `moduleImports` selects when the
#                        configuration names nothing. Any project a
#                        composition lists may register either, for any
#                        class: a `core` is the big hammer, for a module
#                        the class cannot function without; a `default`
#                        is what the project gives every configuration
#                        of the class unless it selects otherwise.
#   frameworkModules     the framework module of a class, forced into
#                        the modules of every configuration of the
#                        class: the core of caisson
#                        itself for the class, which declares the
#                        manifest, the configurations declared inside it
#                        and `caisson.exports`, followed by
#                        `coreModules` of the registry.
#   mkModuleConfiguration
#                        a configuration that is a module evaluation,
#                        from the evaluator step of an integration.
#                        Configurations of any integration can be
#                        declared inside it: the configurations its modules
#                        declare are its children, and what they
#                        export is passed up through it.
{ closure-lib, mkLibOverlay, ... }:
{

  # These functions use `builtins` and the list, attribute set, string
  # and function helpers of caisson-core (`caisson-core.lists` and its
  # neighbours), so this overlay composes in a library that holds no
  # library of nixpkgs. An integration that evaluates modules imports
  # that library itself. The import is the names of the framework
  # under `lib.caisson`, so a library that holds an integration holds
  # those names.
  imports = [ ((mkLibOverlay ../framework) // { key = "framework"; }) ];

  overlay =
    final: prev:
    let

      inherit (final.caisson-core.lists)
        unique
        zipListsWith
        init
        last
        ;
      inherit (final.caisson-core.attrsets) genAttrs filterAttrs;
      inherit (final.caisson-core.strings) hasInfix;
      inherit (final.caisson-core.functions) functionArgs setFunctionArgs;

      # The source a configuration's `ecosystemSrc` selects: the
      # argument is a function of the dependencies passed to mkLib, as
      # `defaultEcosystemSrc` on mkLib is, so a configuration chooses
      # among the dependencies the flake pins. Null when the configuration
      # passes none. `manifest` is the manifest whose `dependencies` it
      # selects from, the lib manifest of the configuration.
      selectedEcosystemSrc =
        context: manifest: explicit:
        if explicit == null then
          null
        else if builtins.isFunction explicit then
          explicit (manifest.dependencies or { })
        else
          throw ''
            ${context}: `ecosystemSrc` is a function of the dependencies passed to mkLib that
            returns the source to use, `ecosystemSrc = dependencies: dependencies.<name>;`,
            but got a ${builtins.typeOf explicit}.
          '';

      resolveEcosystemSrc =
        {
          # the integration's name for its ecosystem, e.g. "nixpkgs"
          name,
          # names the caller in the miss message, e.g. "caisson.nixos"
          context,
        }:
        {
          explicit ? null,
          manifest ? final.caisson-core.libManifest or { },
        }:
        let
          resolved = final.caisson-core.resolve {
            inherit name;
            explicit = selectedEcosystemSrc context manifest explicit;
            defaults = manifest.defaultEcosystemSrc or { };
            dependencies = manifest.dependencies or { };
          };
        in
        if resolved != null then
          resolved
        else
          throw ''
            ${context}: no ${name} ecosystem source. Select one with
            `ecosystemSrc = dependencies: dependencies.<name>;` on the configuration,
            return a `${name}` from the `defaultEcosystemSrc` function of the
            mkLib call, or pin a dependency named `${name}` in the `dependencies` passed
            to mkLib.
          '';

      # How a configuration came by the source of the ecosystem `name`, as
      # its manifest records it under `ecosystems.<name>`. It takes the
      # arguments `resolveEcosystemSrc` takes and follows the same
      # order. `from` names the declaration that supplied the source:
      # `ecosystemSrc` for the selection of the configuration,
      # `defaultEcosystemSrc` for the selection on mkLib, and
      # `dependencies` for the dependency the flake pins under exactly that name.
      # `source` is the name of that dependency among the pinned dependencies,
      # where `pin` records its revision, or null where a selection
      # builds the value in another way. Reading the account forces no
      # source a selection does not read.
      ecosystemAccountOf =
        {
          name,
          context,
        }:
        {
          explicit ? null,
          manifest ? final.caisson-core.libManifest or { },
        }:
        let
          dependencies = manifest.dependencies or { };
        in
        if explicit != null then
          {
            from = "ecosystemSrc";
            source = final.caisson-core.selectedSourceName {
              inherit dependencies;
              selection = dependencies: selectedEcosystemSrc context { inherit dependencies; } explicit;
            };
          }
        else if (manifest.defaultEcosystemSrc or { }) ? ${name} then
          {
            from = "defaultEcosystemSrc";
            source = (manifest.defaultEcosystemSrcNames or { }).${name} or null;
          }
        else if dependencies ? ${name} then
          {
            from = "dependencies";
            source = name;
          }
        else
          resolveEcosystemSrc { inherit name context; } { inherit explicit manifest; };

      named =
        leaf: name:
        let
          n = builtins.stringLength name;
          l = builtins.stringLength leaf;
        in
        name == leaf || (n > l && builtins.substring (n - l - 1) (l + 1) name == "/${leaf}");

      select =
        leaf: registry:
        builtins.map (name: registry.${name}) (builtins.filter (named leaf) (builtins.attrNames registry));

      # The framework module of `class`, over the registry of the
      # class in the composition an evaluation runs in. The core of
      # caisson itself is read from the closure, so it is there
      # however the integration was registered.
      frameworkModules =
        class: registry:
        [
          {
            key = "caisson.${class}";
            imports = [ closure-lib.caisson.modules.${class}.core ];
          }
        ]
        ++ select "core" registry;

      # The module of a configuration of `class` named `name`, in the
      # evaluation whose lib is `lib`: `configModule` when the
      # configuration was given one, else the configuration registered
      # under its name (`lib.caisson.configs.<class>.<name>`), else
      # null. A module given is returned as it was given. Every entry of
      # the registry is keyed `configs.<class>.<name>@<project>`
      # (`lib.caisson.configs`), so the `declaration` event of a module
      # from the registry names its entry, whether it was taken here or
      # given (`declarationEventsOf`).
      configModuleOf =
        {
          lib,
          class,
          name,
          configModule ? null,
        }:
        let
          registered = lib.caisson.configs.${class} or { };
        in
        if configModule != null then
          configModule
        else if name != null then
          registered.${name} or null
        else
          null;

      # A module an integration adds to the modules of a configuration, keyed
      # `key` (`caisson.<class>.<purpose>`) and named by the file `file`
      # (`caisson-<class>:<purpose>`). The wrapper carries the file, so
      # its `declaration` event names it even where `module` is a
      # function, and the key names the module in the history of the
      # evaluation.
      caissonModule =
        {
          key,
          file,
          module,
        }:
        {
          inherit key;
          _file = file;
          imports = [ module ];
        };

      # A stand-in, in the `modules` an integration's `evaluate` returns,
      # for the module list of the ecosystem, where the evaluator
      # receives that list: it is recorded as a single `declaration`
      # event, keyed `key` (`nixos`), from the file `file` of the
      # source `project` (`nixpkgs`), rather than an event for each of
      # its modules.
      ecosystemUnit =
        {
          key,
          project,
          file,
        }:
        {
          _type = "caisson-ecosystem-unit";
          inherit key project file;
        };

      # A file as the record writes it: a file inside a source in the
      # Nix store relative to that source, the way a project's files are
      # named in the project, and any other file as it is.
      inSource =
        file:
        let
          string = toString file;
          parts = final.splitString "/" string;
        in
        if final.hasPrefix "${builtins.storeDir}/" string && builtins.length parts > 4 then
          builtins.concatStringsSep "/" (final.drop 4 parts)
        else
          string;

      # The parts of the key of a module of the registry,
      # `modules.<class>.<name>@<project>`: the registry key and the
      # project that registered the module, null where the library
      # names no project.
      registryPartsOf =
        key:
        let
          parts = final.splitString "@" key;
          registered = final.last parts;
        in
        {
          key = builtins.head parts;
          project = if builtins.length parts < 2 || registered == "" then null else registered;
        };

      # The registry key of a module of the registry, null for any
      # other module.
      registryKeyOf =
        module:
        if builtins.isAttrs module && final.hasPrefix "modules." (module.key or "") then
          (registryPartsOf module.key).key
        else
          null;

      # `modules` as an integration returns it for its `declaration`
      # events, when the list it hands the evaluator names modules of
      # the ecosystem by their files in the source `src`: each such
      # module is an `ecosystemUnit` of the source `name`, keyed by
      # that name, with its file inside the source.
      inEcosystem =
        { name, src }:
        builtins.map (
          module:
          let
            string = if builtins.isPath module || builtins.isString module then toString module else null;
            prefix = "${toString src}/";
          in
          if string != null && final.hasPrefix prefix string then
            ecosystemUnit {
              key = name;
              project = name;
              file = final.removePrefix prefix string;
            }
          else
            module
        );

      # The `declaration` events of a configuration: an event for each
      # element of `modules`, the list the integration hands the
      # evaluator, in that order, with the module list of the ecosystem
      # as the single event of its `ecosystemUnit`. A module selected
      # from the registry carries its registry key in its module key
      # (`lib.caisson.modules`): the event is keyed by the registry key,
      # with the name the registry it was read from gives the entry, and
      # its origin is the project that registered the module and the
      # file of the module, where the module has a file. An entry of a
      # listed project read from the registry of the flake is therefore
      # `modules.<class>.<project>/<name>`, and the same entry read from
      # the library of that project is `modules.<class>.<name>`. A
      # configuration module taken from the registry of configurations
      # is keyed `configs.<class>.<name>` (`configModuleOf`): the event
      # carries that key, and its origin is the project of the lib and
      # the file of the registered configuration. A module of caisson
      # itself is keyed `caisson.<…>`, and its project is caisson. A
      # module given as a path is keyed by the path, and any other
      # module by its position in the list, `inline/<index>`, with the
      # file the module names, where it names a file. Every module
      # caisson adds is keyed, so an `inline/<index>` event is a module
      # the configuration was given as a value. A file inside
      # a source in the Nix store is written relative to that source,
      # the way a project's files are named in the project. `lib` is the
      # lib the configuration is evaluated over.
      declarationEventsOf =
        { lib, modules }:
        let
          libManifest = lib.caisson-core.libManifest or { };
          project = libManifest.name or null;
          # The file of a module, looking through the wrappers that key
          # a module and import it alone.
          fileOf =
            module:
            if builtins.isPath module || builtins.isString module then
              inSource module
            else if builtins.isAttrs module && module ? _file then
              inSource module._file
            else if builtins.isAttrs module && builtins.length (module.imports or [ ]) == 1 then
              fileOf (builtins.head module.imports)
            else
              null;
          keyed = prefix: module: builtins.isAttrs module && lib.hasPrefix prefix (module.key or "");
          eventOf =
            index: module:
            {
              operation = "declaration";
            }
            // (
              if (module._type or null) == "caisson-ecosystem-unit" then
                {
                  inherit (module) key;
                  origin = {
                    inherit (module) project file;
                  };
                }
              else if keyed "modules." module then
                let
                  registered = registryPartsOf module.key;
                in
                {
                  inherit (registered) key;
                  origin = {
                    inherit (registered) project;
                    file = fileOf module;
                  };
                }
              else if keyed "configs." module then
                let
                  registered = registryPartsOf module.key;
                in
                {
                  inherit (registered) key;
                  origin = {
                    project = if registered.project == null then project else registered.project;
                    file = fileOf module;
                  };
                }
              else if keyed "caisson." module then
                {
                  inherit (module) key;
                  origin = {
                    project = "caisson";
                    file = fileOf module;
                  };
                }
              else if builtins.isPath module then
                {
                  key = inSource module;
                  origin = {
                    inherit project;
                    file = inSource module;
                  };
                }
              else
                {
                  key = "inline/${toString index}";
                  origin = {
                    inherit project;
                    file = fileOf module;
                  };
                }
            );
        in
        lib.imap0 eventOf modules;

      # How a configuration of the class `class`, constructed with `args`,
      # selected its modules, as its manifest records it in
      # `moduleImports`:
      #
      # - `act`: `default` when the configuration took the default of
      #   the class, `appended` when it gave `extraModuleImports`
      #   alone, and `reset` when it gave `moduleImports`, which
      #   replaces the default;
      # - `position`: where the configuration gave `moduleImports` or
      #   `extraModuleImports`, the file and line number, null for
      #   `default`;
      # - `default`: the default selection of the class for this
      #   configuration, whatever the act, as
      #   `{ key; level; file; }` entries: first the entries of the
      #   registry named `default`, with a null `level` and `file`,
      #   then what each level above added
      #   (`caisson.forChildren.extraDefaultModuleImports`), with the
      #   name path of the level and the file that defines it, then
      #   what each level above added for the nearest configurations of
      #   the class where this configuration is one of them
      #   (`caisson.forNearestChildren.extraDefaultModuleImports`), with
      #   its level and file and `nearest = true`;
      # - `selected`: the registry keys of the modules selected, null
      #   for a module that is not from the registry.
      selectionAccountOf =
        { class, args }:
        { lib, manifest }:
        let
          registry = lib.caisson.modules.${class} or { };
          given = args.moduleImports or null;
          extra = args.extraModuleImports or null;
          given' =
            if given != null then
              "moduleImports"
            else if extra != null then
              "extraModuleImports"
            else
              null;
        in
        {
          act =
            if given != null then
              "reset"
            else if extra != null then
              "appended"
            else
              "default";
          position =
            let
              position = positionOf (builtins.unsafeGetAttrPos given' args);
            in
            if given' == null || position == null then null else position // { file = inSource position.file; };
          default =
            builtins.map (module: {
              key = registryKeyOf module;
              level = null;
              file = null;
            }) (select "default" registry)
            ++ builtins.concatMap (
              entry:
              builtins.map (
                module:
                {
                  key = registryKeyOf module;
                  inherit (entry) level file;
                }
                // (if entry.nearest or false then { nearest = true; } else { })
              ) (entry.select lib)
            ) (manifest.defaultModuleImports.${class} or [ ]);
          selected = builtins.map registryKeyOf (
            moduleImportsOf class { inherit lib manifest; } args registry
          );
        };

      # The arguments a configuration, constructed with `args`, handed
      # to its evaluator as it gave them, as its manifest records them
      # in `evaluatorArgs`. Every entry point takes `specialArgs`, which
      # the integration merges over the special arguments it supplies.
      # The `WithEcosystemArgs` variant takes `ecosystemArgs`, which the
      # integration merges over the evaluator's call last. For each of
      # the two that the configuration gave, the record holds:
      #
      # - `names`: the names of the attributes it gave;
      # - `position`: where the configuration gave it, the file and
      #   line number.
      #
      # The record holds the names alone, since a value may be a
      # function or a whole package set. A configuration that gave
      # neither records `{ }`.
      evaluatorArgsAccountOf =
        args:
        let
          accountOf =
            argument:
            let
              given = args.${argument} or null;
              position = positionOf (builtins.unsafeGetAttrPos argument args);
            in
            if given == null then
              [ ]
            else
              [
                {
                  name = argument;
                  value = {
                    names = builtins.attrNames given;
                    position = if position == null then null else position // { file = inSource position.file; };
                  };
                }
              ];
        in
        builtins.listToAttrs (accountOf "specialArgs" ++ accountOf "ecosystemArgs");

      # The selection of a configuration over the registry of its class,
      # from the arguments of the configuration, as a function of that
      # registry: what `moduleImports` selects, and with none
      # given the default of the class, every entry named `default`
      # followed by what the configurations above it added for the
      # class (`caisson.forChildren.extraDefaultModuleImports`), then
      # what they added for the nearest configurations of the class
      # where this configuration is one of them
      # (`caisson.forNearestChildren.extraDefaultModuleImports`), each
      # applied to the lib of the configuration.
      #
      # `extraModuleImports` of the configuration is appended to
      # either: it adds to the selection where `moduleImports`
      # replaces it, so a configuration that adds a module keeps the
      # default of its class.
      moduleImportsOf =
        class:
        { lib, manifest }:
        args: registry:
        let
          given = args.moduleImports or null;
          extra = args.extraModuleImports or null;
        in
        (
          if given != null then
            given registry
          else
            select "default" registry
            ++ builtins.concatMap (entry: entry.select lib) (manifest.defaultModuleImports.${class} or [ ])
        )
        ++ (if extra == null then [ ] else extra registry);

      # The package sets available to a configuration, by package config
      # name: the package configs its manifest holds, each projected to
      # its set for `system`. `context` names the entry point and `what`
      # the configuration, for the message of a config that builds no
      # set for that system.
      pkgSetsForSystem =
        { context, what }:
        manifest: system:
        builtins.mapAttrs (
          name: config:
          (config.children.nixpkgs.${system} or (throw ''
            ${context}: the package config `${name}` builds no set for ${system},
            which ${what} needs. Add the system to `caisson.nixpkgs.systems`
            in the config's module.
          '')
          ).value
        ) (manifest.pkgSets or { });

      # The package set a configuration runs on: the package set
      # selection that applies to its manifest, applied to the package
      # sets available to it. A selection is a function that receives
      # those sets, as an attribute set by package config name, and
      # returns the set to run on. The `defaultPkgs` argument of a
      # constructor makes a selection for that configuration, and the
      # configurations declared inside it run on it unless they or a
      # configuration between them select another
      # (`mkModuleConfiguration` records it). A configuration that
      # passes none runs on what the nearest configuration above it
      # selected. Where no configuration from the caisson top down to this
      # configuration selected, it runs on the set named `default`. Every integration
      # whose configurations run on a package set selects it here.
      pkgSetOf =
        { context, what }:
        manifest: pkgSets:
        if (manifest.defaultPkgs or null) != null then
          manifest.defaultPkgs pkgSets
        else
          pkgSets.default or (throw ''
            ${context}: ${what} runs on the package set named `default`,
            since no configuration from the caisson top down to it selects one, and the
            package sets available here are ${
              if pkgSets == { } then "none" else builtins.concatStringsSep ", " (builtins.attrNames pkgSets)
            }. Declare a package config named `default` with `pkgSets` on mkLib,
            or select a set where a configuration is constructed
            (`defaultPkgs = pkgSets: pkgSets.<name>;`).
          '');

      # Which package config a configuration runs on, as its manifest
      # records it under `pkgSet`. `name` is the name of the package
      # config whose set the selection that applies to `manifest` returns.
      # It is read from the selection applied to `pkgSets` tagged with
      # their names, so it is null where the selection returns a set it
      # builds in another way. `level` is the name path of the
      # configuration that made the selection: the configuration itself
      # when `own` says it was constructed with `defaultPkgs`, else the
      # nearest configuration above that selected for the
      # configurations declared inside it. Where no configuration selects,
      # `name` is `default` and `level` is null, as `pkgSetOf` runs the
      # configuration on the set named `default`. `perSystem` says
      # whether the configuration is evaluated per system. A
      # configuration evaluated once for every system runs on no single
      # set, so its `name` is null, and `pkgSets` is not read.
      pkgSetAccountOf =
        { own, perSystem }:
        manifest: pkgSets:
        let
          selection = manifest.defaultPkgs or null;
          tag = "_caissonPkgSetName";
          tagged = builtins.mapAttrs (name: set: set // { ${tag} = name; }) pkgSets;
          selected = selection tagged;
        in
        if selection == null then
          {
            name = if perSystem then "default" else null;
            level = null;
          }
        else
          {
            name =
              if !perSystem then
                null
              else if builtins.isAttrs selected then
                selected.${tag} or null
              else
                null;
            level = if own then final.caisson-core.namePathOf manifest else selectionLevelAbove manifest;
          };

      # The name path of the configuration above `manifest` that made
      # the package set selection that applies to `manifest`: the nearest
      # parent that selects for the configurations declared inside it with
      # `caisson.forChildren.defaultPkgs`, or else the level a parent
      # records for the selection it runs on. A system between a configuration
      # and its parent is passed over. Null where no configuration
      # above selects.
      selectionLevelAbove =
        manifest:
        let
          parent = manifest.parent or null;
        in
        if parent == null then
          null
        else if ((parent.forChildren or { }).defaultPkgs or null) != null then
          final.caisson-core.namePathOf parent
        else if parent ? pkgSet then
          parent.pkgSet.level
        else
          selectionLevelAbove parent;

      # The additions to the default selections that a container of
      # options gives, `caisson.forChildren` or
      # `caisson.forNearestChildren`, as caisson-core takes them: by
      # class, a list holding the selection with the file that defines
      # it for its class, the last definition where several modules
      # define the class. `containerOptions` are the options of the
      # container and `containerConfig` its values.
      additionsOf =
        containerOptions: containerConfig:
        builtins.mapAttrs (
          class: selection:
          let
            defining = builtins.filter (definition: definition.value ? ${class}) (
              containerOptions.extraDefaultModuleImports.definitionsWithLocations
            );
          in
          [
            {
              select = selection;
              file = if defining == [ ] then null else inSource (final.last defining).file;
            }
          ]
        ) containerConfig.extraDefaultModuleImports;

      # The names of the namespaces of the lib a configuration runs on, as
      # its manifest records them under `namespaces`: for each entry of
      # `lib.caisson`, the names of its attributes where it is an
      # attribute set and null where it is not, and the names of
      # `lib.caisson-core`. Names only, so nothing is forced past the
      # keys of the namespaces.
      namespacesOf =
        lib:
        let
          namesOf =
            value:
            let
              isSet = builtins.tryEval (builtins.isAttrs value);
            in
            if isSet.success && isSet.value then builtins.attrNames value else null;
        in
        {
          caisson = builtins.mapAttrs (_: namesOf) (lib.caisson or { });
          caisson-core = builtins.attrNames (lib.caisson-core or { });
        };

      # The dependencies of a configuration that adds `dependencies` to
      # those of the configuration it is declared inside, as its
      # manifest records them. A flake-parts configuration that holds
      # the checks of a flake declares the pins only its checks need
      # this way, so the pin file of the caisson top stays free of them:
      #
      #   caisson.flake-parts.configurations.checks = lib.caisson.flake-parts.mkConfiguration {
      #     inherit (lib.caisson.pins.flake-compat ../../../tests/dependencies) dependencies;
      #   };
      #
      # `dependencies` of the record are the dependencies of the parent
      # with the added dependencies beside them, so the configuration
      # and the configurations declared inside it are evaluated with
      # both. A name that the parent already pins keeps the dependency
      # of the parent: an added dependency cannot replace a dependency
      # of the caisson top. The added dependency of that name is
      # recorded in `shadowedDependencies` and is used nowhere. Its
      # entry in the pin files that hold it still serves the `follows`
      # lines written in those files, which can name only the inputs of
      # those files.
      #
      # Each added dependency keeps the `pin` its reader gave it, with
      # its pin files relative to the root of the caisson top, as mkLib
      # records the pin files of the dependencies of the caisson top.
      # `topside` reads the pin files of each dependency from there, so
      # a dependency added here is moved by the writer of its pin system
      # in the directory that holds those files. The caisson top passes
      # its dependencies to mkLib, so `dependencies` here is refused for
      # the configuration at the caisson top.
      dependencyRecordOf =
        {
          what,
          manifest,
          dependencies,
        }:
        let
          parent = manifest.parent;
          above = parent.dependencies or { };
          root = manifest.root or null;
          added =
            if (parent.type or "lib") == "lib" then
              throw ''
                caisson: ${what} is given `dependencies`. A configuration is given
                `dependencies` when it is declared inside another configuration, and this
                configuration is the caisson top. Pass the dependencies of the caisson top
                to mkLib.
              ''
            else if dependencies == null then
              { }
            else if builtins.isAttrs dependencies then
              dependencies
            else
              throw ''
                caisson: ${what} takes `dependencies` as an attribute set of pinned
                dependencies by name, as a pin reader returns them
                (`inherit (lib.caisson.pins.flake-compat ./tests/dependencies) dependencies;`),
                and was given a ${builtins.typeOf dependencies}.
              '';
          relativeTo =
            prefix: dir:
            let
              path = builtins.toString dir;
              length = builtins.stringLength prefix;
            in
            if path == prefix then
              ""
            else if builtins.substring 0 (length + 1) path == prefix + "/" then
              builtins.substring (length + 1) (builtins.stringLength path) path
            else
              null;
          recorded =
            dependency:
            let
              pin = dependency.pin or null;
              relative =
                if pin == null || !(pin ? dir) || root == null then
                  null
                else
                  relativeTo (builtins.toString root.outPath) pin.dir;
            in
            if relative == null then
              dependency
            else
              dependency
              // {
                pin = builtins.removeAttrs pin [ "dir" ] // {
                  files = builtins.mapAttrs (
                    _: file: if relative == "" then file else relative + "/" + file
                  ) pin.files;
                };
              };
          shadowed = builtins.filter (name: above ? ${name}) (builtins.attrNames added);
        in
        {
          dependencies = above // builtins.mapAttrs (_: recorded) (builtins.removeAttrs added shadowed);
          shadowedDependencies = builtins.mapAttrs (_: recorded) (
            builtins.intersectAttrs (genAttrs shadowed (_: null)) added
          );
        };

      # A configuration that is a module evaluation. `type` is the
      # name of the integration and `perSystem` whether it evaluates a
      # configuration per system, as caisson-core.mkConfiguration
      # takes them. `evaluate` is the evaluator step of the
      # integration: it takes the lib and manifest the configuration is
      # evaluated with, `{ lib, manifest }`, and returns `value`, the
      # evaluation result as the evaluator returned it, `outputs`, the references into it that
      # the integration declares, and `config` where the evaluated
      # options are not `value.config`. Its module list carries
      # `frameworkModules` of its class.
      #
      # The configurations its modules declare under
      # `caisson.<integration>.configurations`, of any integration,
      # are its children, and `caisson.exports`, which carries what
      # they pass up, is its `exports` output. An integration whose
      # evaluator finalizes the children returns them as
      # `children`, by integration and then name, and they are its
      # children in place of those values. A deferred configuration
      # (`caisson-core.mkDeferredConfiguration`) finalizes the deferred
      # configurations declared inside it this way, with their part of
      # its args.
      #
      # `evaluate` may also return `argsNeeded`, the args a deferred
      # configuration takes, and `discoverArgs`, the function of
      # `{ system }` that returns the program which finds them, or
      # null. The manifest carries both, as caisson-core describes
      # them. A configuration whose `evaluate` returns neither takes no
      # args.
      #
      # `defaultPkgs` is the selection of a package set the configuration
      # was constructed with, null when it was given none. It is
      # recorded on the manifest. The configuration runs on it, and so
      # do the configurations declared inside it unless they or a
      # configuration between them select another.
      #
      # `exportsTo` says how the configuration is published: `attrset`,
      # the output attribute set (`nixosConfigurations`), and `value`,
      # the function from the manifest of the configuration to what is
      # published. It may carry `name`, for an integration whose
      # configurations are known by a name other than the name they are
      # declared under: a function of `{ name, manifest }`, the name
      # the configuration is passed up under and its manifest,
      # returning `value`, the name to publish it under, and
      # optionally `description`, a sentence saying what it did. It may
      # carry `single`, for an output that holds the configuration
      # named for that output, and `bySystem`, for an output keyed by the
      # system of each evaluation result first (`packages.<system>.<name>`). It
      # may carry `only`, a function of the manifest that says whether
      # the configuration is published there at all; a configuration it
      # leaves out is still passed up.
      # `exportsTo` may also be a list of such exports, for an
      # integration whose configurations are published in more than
      # one output. It is recorded on the manifest, with
      # `exportsToPosition`, the file and line number where the integration
      # wrote it, and applied where the configuration is passed up
      # (`entriesOf`). Null for a configuration that is not published
      # under a name.
      #
      # `activation` is given by an integration whose configurations
      # are activated on a computer or for a user: NixOS, nix-darwin and
      # system-manager configurations, home-manager configurations, hjem
      # configurations. It holds
      # functions of a manifest of the configuration. `identity`
      # returns the store path that names what the activation applies,
      # computed from the result of the childless evaluation, or null
      # where there is none. `standsAlone`, when true, says the
      # configuration is applied by itself, as a NixOS configuration is
      # activated on the computer it describes, so that it checks no
      # configuration above it. `marker` returns the path of the file the activation
      # writes that identity into, as shell text, which may name
      # variables such as `$HOME`. It is recorded on the manifest. A
      # configuration with an activation declared inside another such configuration checks
      # the marker of the nearest such configuration above it when it
      # is activated (`driftCheckOf`). `profileAdapter`, where an
      # integration gives it, is a function of a full manifest of the
      # configuration that returns the Nix profiles of the
      # configuration as data: `activate`, the program that activates
      # it, and `profiles`, by name, each with its `path`, the store
      # path it `holds` once the configuration is applied, and `setBy`,
      # what sets it. The home-manager integration gives one. Null for
      # a configuration that is not activated.
      #
      # `selection` is `{ class; args; }`, the class of the configuration
      # and the arguments the configuration was constructed with, from
      # which the manifest records how the configuration selected its
      # modules as `moduleImports` (`selectionAccountOf`), and which
      # arguments it handed to the evaluator as it gave them as
      # `evaluatorArgs` (`evaluatorArgsAccountOf`). Null for a
      # configuration whose modules are not selected from a class.
      #
      # What the modules give the configurations declared inside is read from
      # `caisson.forChildren` and `caisson.forNearestChildren`
      # (`additionsOf`).
      #
      # `checks` is a function that returns the default checks of the
      # integration for an evaluation result that has a system, by
      # name. caisson calls it with `{ outputs, system, pkgs, pkgSets }`:
      # `outputs` are the outputs of the evaluation result as its
      # manifest holds them, `system` is the system of the evaluation
      # result, `pkgSets` are the package sets for that system by the
      # name of the package config, and `pkgs` is the set the selection
      # of the configuration picks of them. Each check it returns is
      # `{ derivation; category; description; }`: `derivation` is the
      # derivation of the check for that system, `category` is the name
      # of a category of checks, and `description` is a sentence saying
      # what the check checks. The nixos integration declares the check
      # `toplevel` with
      # `checks = { outputs, ... }: { toplevel = { derivation = outputs.toplevel; … }; }`.
      # A configuration annotates a default check, or turns it off,
      # with the entry of the same name in `caisson.checks`. An
      # evaluation result that has no system carries no default checks.
      #
      # The record writes two code positions for a default check: the
      # position where the integration passes `checks`, and the
      # position of the definition that declares the configuration
      # inside its parent, the line of
      # `caisson.nixos.configurations.nas-1 = …` for the NixOS
      # configuration `nas-1`. A caisson top is declared inside no
      # configuration, so its default checks carry the first position
      # alone. Each configuration records in `childrenCode` the
      # positions of the definitions that declare the configurations
      # inside it, by integration and then name, and a configuration
      # reads its position there in the result of the childless
      # evaluation of its parent.
      #
      # A caisson top also carries the check `registries`
      # (`registriesCheckOf`), which reads `registryEntries`, the
      # record of the registry entries each evaluation result
      # evaluated (`registryEntriesOf`).
      # `checkCategories` are the categories of checks the integration
      # declares, by name, each `{ description; volatile ? false; }`,
      # for the categories its default checks name beyond those caisson
      # declares (`caisson.checkCategories`).
      #
      # The manifest records the checks of the configuration in
      # `checks`, by system and then name (`checksOfConfiguration`):
      # the default checks of the integration and the checks the modules
      # of the configuration declare, each with its `derivation`,
      # `category`, `description`, `enable` and `code`. It records the
      # categories of checks the integration and the modules declare in
      # `checkCategories`, and the stages the modules declare in
      # `checkStages`. The checks gathered at and inside the
      # configuration are `checks` of its outputs (`checksOf`).
      #
      # `dependencies` are pinned dependencies the configuration adds to
      # the dependencies of the configuration it is declared inside, in
      # the shape a pin reader returns them. The flake-parts integration
      # passes them from the `dependencies` argument of its
      # `mkConfiguration`, and an integration that passes none leaves
      # the argument out. The manifest of a configuration given the
      # argument records `dependencies` and `shadowedDependencies`
      # (`dependencyRecordOf`). Whether the argument is given decides
      # the fields of the manifest, and its value is read when those
      # fields are read, so a configuration whose manifest nothing reads
      # reads no pin file.
      mkModuleConfiguration =
        args@{
          type,
          perSystem ? false,
          defaultPkgs ? null,
          exportsTo ? null,
          activation ? null,
          selection ? null,
          checks ? _: { },
          checkCategories ? { },
          dependencies ? null,
          evaluate,
        }:
        let
          # Where the integration writes its default checks and its
          # categories, for the `code` of each in the record.
          codeOfArgument =
            name:
            let
              position = positionOf (builtins.unsafeGetAttrPos name args);
            in
            if position == null then [ ] else [ (position // { file = inSource position.file; }) ];
          defaultChecksCode = codeOfArgument "checks";
          declaredCategories = builtins.mapAttrs (_: category: {
            inherit (category) description;
            volatile = category.volatile or false;
            code = codeOfArgument "checkCategories";
          }) checkCategories;
        in
        final.caisson-core.mkConfiguration {
          inherit type perSystem;
          # The class of the configuration, where the additions for the
          # nearest children of that class connect.
          class = if selection == null then null else selection.class;
          recordFromEvaluation = [
            "checkCategories"
            "checks"
            "checkStages"
            "childrenCode"
            "ecosystems"
            "namespaces"
            "pkgSet"
            "registryEntries"
          ]
          ++ (if selection == null then [ ] else [ "moduleImports" ])
          ++ (
            if args ? dependencies then
              [
                "dependencies"
                "shadowedDependencies"
              ]
            else
              [ ]
          );
          record =
            (if defaultPkgs == null then { } else { inherit defaultPkgs; })
            // (
              if exportsTo == null then
                { }
              else
                {
                  inherit exportsTo;
                  exportsToPosition = positionOf (builtins.unsafeGetAttrPos "exportsTo" args);
                }
            )
            // (if activation == null then { } else { inherit activation; })
            # Which arguments the configuration handed to the evaluator
            # as it gave them, and where.
            // (if selection == null then { } else { evaluatorArgs = evaluatorArgsAccountOf selection.args; });
          evaluate =
            given:
            let
              evaluated = evaluate given;
              config = evaluated.config or evaluated.value.config;
              options = evaluated.options or evaluated.value.options;
              caissonOptions = options.caisson or { };

              outputs = (evaluated.outputs or { }) // {
                exports = config.caisson.exports;
                checks = checksOf given.manifest;
              };

              what = "the ${type} configuration ${
                if given.manifest ? name then "`${toString given.manifest.name}`" else "at the caisson top"
              }";

              # The configuration that declares this configuration: the
              # parent, or, for an evaluation result of a configuration
              # evaluated per system, the parent of its system. Null for
              # a caisson top, whose parent is the manifest of the lib.
              declaring =
                let
                  parent = given.manifest.parent or null;
                  above = if (parent.type or null) == "system" then parent.parent or null else parent;
                in
                if above == null || (above.type or "lib") == "lib" then null else above;

              # The positions of the definitions that declare this
              # configuration inside the configuration that declares it,
              # as that configuration records them in `childrenCode`.
              declaringCode =
                let
                  recorded = if declaring == null then null else declaring.childrenCode or null;
                in
                if recorded == null || !(given.manifest ? name) then
                  [ ]
                else
                  (recorded.${type} or { }).${toString given.manifest.name} or [ ];

              # The checks of the configuration for a system, from the
              # declarations of its modules: the default checks of the
              # integration for that system, the check `registries` at a
              # caisson top, and the checks the modules declare. caisson
              # calls `checks` with the outputs, the system, the package
              # sets for that system, by the name of the package config,
              # as `pkgSets`, and the set the selection of the
              # configuration picks of them as `pkgs`.
              checksFor =
                system:
                let
                  messages = {
                    context = "caisson.checks";
                    what = "the checks of ${what} for ${system}";
                  };
                  pkgSets = pkgSetsForSystem messages given.manifest system;
                  pkgs = pkgSetOf messages given.manifest pkgSets;
                  ofIntegration =
                    builtins.mapAttrs
                      (
                        _: check:
                        check
                        // {
                          code = defaultChecksCode ++ declaringCode;
                        }
                      )
                      (checks {
                        inherit
                          outputs
                          system
                          pkgs
                          pkgSets
                          ;
                      });
                  ofTop =
                    if declaring == null then
                      registriesCheckOf {
                        inherit system;
                        inherit (given) manifest;
                      }
                    else
                      { };
                in
                checksOfConfiguration {
                  inherit what type system;
                  defaults = ofTop // ofIntegration;
                };

              # The system of this evaluation result: the system it is
              # evaluated for, or, for a configuration declared inside an
              # evaluation result that has a system, the system of the
              # nearest such evaluation result above it. A disko
              # configuration declared inside a NixOS configuration
              # evaluated for aarch64-linux has the system aarch64-linux.
              # Null where neither has a system.
              system =
                let
                  above = builtins.filter (ancestor: ancestor ? system) (given.manifest.ancestors or [ ]);
                in
                if given.manifest ? system then
                  given.manifest.system
                else if above == [ ] then
                  null
                else
                  (last above).system;

              declaredHere =
                if caissonOptions ? checks then
                  checkDeclarationsOf {
                    option = caissonOptions.checks;
                    value = config.caisson.checks;
                  }
                else
                  { };

              # The flake-parts and structural integrations return the
              # declarations of each system as `checkDeclarations`, read
              # from `perSystem`. In any other configuration the modules
              # declare the checks in `caisson.checks`, for the system of
              # the evaluation result.
              recordedChecks =
                if evaluated ? checkDeclarations then
                  builtins.mapAttrs checksFor evaluated.checkDeclarations
                else if system != null then
                  { ${system} = checksFor system declaredHere; }
                else if declaredHere == { } then
                  { }
                else
                  throw ''
                    caisson: ${what} has the checks ${
                      builtins.concatStringsSep ", " (builtins.map (name: "`${name}`") (builtins.attrNames declaredHere))
                    }, and its evaluation result has no system: it is not evaluated for a
                    system, and no configuration it is declared inside is. Declare the checks in
                    a configuration evaluated for a system, such as a NixOS configuration, or
                    under `perSystem` of a structural or flake-parts configuration.
                  '';

              # The positions of the definitions that declare the
              # configurations inside this configuration, by integration
              # and then name (`childrenCodeOf`).
              recordedChildrenCode = childrenCodeOf options;

              # The registry entries this evaluation result evaluated,
              # with the `caisson` options they define
              # (`registryEntriesOf`). An evaluator that returns no import
              # graph of its modules gives no record of them.
              recordedRegistryEntries =
                let
                  graph =
                    evaluated.graph
                      or (if builtins.isAttrs evaluated.value then evaluated.value.graph or null else null);
                in
                if graph == null then { } else registryEntriesOf { inherit graph options; };

              recordedCategories = categoriesUnion [
                declaredCategories
                (
                  if caissonOptions ? checkCategories then
                    builtins.mapAttrs (name: category: {
                      inherit (category) description volatile;
                      code = definitionCodeOf caissonOptions.checkCategories name;
                    }) config.caisson.checkCategories
                  else
                    { }
                )
              ];

              recordedStages =
                if caissonOptions ? checkStages then
                  builtins.mapAttrs (name: stage: {
                    inherit (stage) description select;
                    code = definitionCodeOf caissonOptions.checkStages name;
                  }) config.caisson.checkStages
                else
                  { };
            in
            {
              inherit (evaluated) value;
              inherit outputs;
              children =
                evaluated.children or (given.lib.caisson.integrations.childrenOf { inherit options config; });
              # What the modules give the configurations declared inside
              # (`caisson.forChildren`).
              forChildren = {
                extraDefaultModuleImports = additionsOf options.caisson.forChildren config.caisson.forChildren;
                defaultPkgs = config.caisson.forChildren.defaultPkgs;
                systems = config.caisson.forChildren.systems;
                inherit (config.caisson.forChildren) unsafeCrossChildReferences;
              };
              # What the modules give the nearest configurations of a
              # class declared inside (`caisson.forNearestChildren`).
              forNearestChildren = {
                extraDefaultModuleImports = additionsOf options.caisson.forNearestChildren config.caisson.forNearestChildren;
                inherit (config.caisson.forNearestChildren) unsafeCrossChildReferences;
              };
              # What the modules give the configurations of a class
              # declared directly inside (`caisson.forDirectChildren`).
              forDirectChildren = {
                extraDefaultModuleImports = additionsOf options.caisson.forDirectChildren config.caisson.forDirectChildren;
                inherit (config.caisson.forDirectChildren) unsafeCrossChildReferences;
              };
              # What the evaluator received, as `declaration` events:
              # the integration's `evaluate` returns `modules`, the list
              # it handed the evaluator, with an `ecosystemUnit` where
              # the module list of the ecosystem is. An evaluator that
              # evaluates modules it was handed inside a module of the
              # configuration records those modules as `events` beside
              # them: the nixos-test integration records the modules of
              # each node of a test, which the test framework evaluates.
              events =
                declarationEventsOf {
                  inherit (given) lib;
                  modules = evaluated.modules or [ ];
                }
                ++ (evaluated.events or [ ]);
              record = {
                # The checks of the configuration, by system and then
                # name, the categories of checks and the stages it
                # declares.
                checks = recordedChecks;
                checkCategories = recordedCategories;
                checkStages = recordedStages;
                # Where the configurations declared inside are declared,
                # and the registry entries the evaluation result
                # evaluated.
                childrenCode = recordedChildrenCode;
                registryEntries = recordedRegistryEntries;
                # Where each part of the stack the configuration used came
                # from (`ecosystemAccountOf`): the library of the lib it
                # runs on, and each ecosystem the integration resolved,
                # which its `evaluate` returns as `ecosystems`.
                ecosystems = {
                  nixpkgs-lib = ecosystemAccountOf {
                    name = "nixpkgs-lib";
                    context = "the nixpkgs-lib entry";
                  } { manifest = given.lib.caisson-core.libManifest or { }; };
                }
                // (evaluated.ecosystems or { });
                # The names of the namespaces of the lib the configuration
                # runs on (`namespacesOf`).
                namespaces = namespacesOf given.lib;
              }
              # Which package config the configuration runs on and the
              # configuration that selected it (`pkgSetAccountOf`). A
              # configuration evaluated once for every system runs on
              # no single set, so it records the level alone.
              // {
                pkgSet =
                  pkgSetAccountOf
                    {
                      own = defaultPkgs != null;
                      inherit perSystem;
                    }
                    given.manifest
                    (
                      pkgSetsForSystem {
                        context = "the pkgSet record";
                        what = "the configuration";
                      } given.manifest given.manifest.system
                    );
              }
              # How the configuration selected its modules.
              // (if selection == null then { } else { moduleImports = selectionAccountOf selection given; })
              # The dependencies the configuration and the configurations
              # declared inside it are evaluated with.
              // (
                if args ? dependencies then
                  dependencyRecordOf {
                    inherit what dependencies;
                    inherit (given) manifest;
                  }
                else
                  { }
              );
            }
            # The args of a deferred configuration and the program that
            # finds them, where the integration's `evaluate` returns
            # them.
            // (if evaluated ? argsNeeded then { inherit (evaluated) argsNeeded; } else { })
            // (if evaluated ? discoverArgs then { inherit (evaluated) discoverArgs; } else { });
        };

      # The body of both entry points, from the caisson arguments a
      # pattern admitted: `compose` takes them and returns an attrset
      # holding `ecosystemArgs`, the evaluator's call as composed,
      # beside whatever `evaluate` needs; `evaluate` takes that attrset
      # and the call to make. `ecosystemArgs`, which only the pattern
      # of the `WithEcosystemArgs` variant admits, is merged over the composed call verbatim,
      # last.
      mkEvaluation =
        { compose, evaluate }:
        args:
        let
          composed = compose args;
        in
        evaluate composed (composed.ecosystemArgs // (args.ecosystemArgs or { }));

      # The `mkTopConfiguration` of an integration: it takes the
      # arguments of `mkConfiguration`, finalizes the configuration
      # with no parent, and applies `top` to the manifest. It has the
      # argument pattern of `mkConfiguration`, so a reader of
      # `builtins.functionArgs` sees the same arguments.
      topConfiguration =
        top: mkConfiguration:
        setFunctionArgs (args: top (final.caisson-core.finalizeTop (mkConfiguration args))) (
          functionArgs mkConfiguration
        );

      # The class a module states it belongs to, or null where it
      # states none. A module states its class in one of two ways. A
      # module with `_class` states it as the module system reads it.
      # A module read from the registry (`lib.caisson.modules.<class>.<name>`)
      # carries the class in its key, `modules.<class>.<name>@<project>`,
      # and a registered configuration carries it in
      # `configs.<class>.<name>@<project>` (`keyedModules` and
      # `keyedConfigs` in lib-overlays/framework). A function or a path
      # states no class, because reading one would call the function or
      # import the file.
      classOfModule =
        module:
        let
          key = module.key or null;
          registered =
            if builtins.isString key then
              builtins.match "(registered\\.)?(modules|configs)\\.([^.]+)\\..*@.*" key
            else
              null;
        in
        if !builtins.isAttrs module then
          null
        else if (module._class or null) != null then
          module._class
        else if registered != null then
          builtins.elemAt registered 2
        else
          null;

      # The option type of a module of the class `class`: the
      # `deferredModule` type of nixpkgs, which refuses a definition
      # whose module states another class (`classOfModule`). A module
      # that states no class is taken as it is, and the module
      # evaluation it is imported into checks what it declares.
      moduleTypeOf =
        lib: class:
        let
          checked =
            loc: def:
            let
              stated = classOfModule def.value;
            in
            if stated == null || stated == class then
              def
            else
              throw ''
                The definition of `${lib.showOption loc}` in `${def.file}` is a module of
                the class `${stated}`, and the option takes a module of the class `${class}`.
              '';
          # The module system rebuilds the type of an option from the
          # type it is declared with: `substSubModules` when it adds the
          # modules of the declaration, `typeMerge` when the option is
          # declared twice. Each rebuilt type checks the class again.
          classChecked =
            base:
            base
            // {
              description = "module of the class `${class}`";
              # Each definition is checked when the option is merged,
              # before the merged module is imported anywhere.
              merge =
                loc: defs:
                let
                  checkedDefs = map (checked loc) defs;
                  allChecked = builtins.foldl' (forced: def: builtins.seq def forced) null checkedDefs;
                in
                builtins.seq allChecked (base.merge loc checkedDefs);
              substSubModules = modules: classChecked (base.substSubModules modules);
              typeMerge =
                functor:
                let
                  merged = base.typeMerge functor;
                in
                if merged == null then null else classChecked merged;
            };
        in
        classChecked lib.types.deferredModule;

      # The integration a configuration belongs to, read from what
      # finalizing it returned: the type of the manifest, or of the
      # evaluations of a configuration evaluated per system, null where
      # it has none.
      typeOfFinalized =
        finalized:
        if !builtins.isAttrs finalized then
          null
        else if isManifest finalized || final.caisson-core.isDeferred finalized then
          finalized.type
        else if finalized == { } then
          null
        else
          (builtins.head (builtins.attrValues finalized)).type or null;

      # The option type of a configuration of the integration
      # `integration`: what `lib.caisson.<integration>.mkConfiguration`
      # returns, a function of exactly `{ name, parent }`, or a deferred
      # configuration (`caisson-core.mkDeferredConfiguration`). A
      # configuration of another integration is refused when it is
      # finalized, with the option and the file that define it. The
      # type reads the integration of a configuration from the manifest
      # that finalizing it returns, and it forces nothing more of that
      # manifest than its `type`. A deferred configuration states its
      # type before any args are given, so the type reads it there.
      configurationTypeOf =
        lib: integration:
        let
          isConfiguration =
            value:
            builtins.isFunction value
            &&
              builtins.functionArgs value == {
                name = false;
                parent = false;
              };
          refusal =
            loc: def: declared:
            let
              defined = ''
                `${lib.showOption loc}` in `${def.file}`
                is defined with a ${declared} configuration, and the option takes a
                ${integration} configuration.'';
            in
            if (lib.caisson.${declared} or { }) ? configurationsModule then
              ''
                ${defined} Declare it under `caisson.${declared}.configurations`.
              ''
            else
              ''
                ${defined} No integration of this library declares
                `caisson.${declared}.configurations`, so a ${declared} configuration
                cannot be declared inside another configuration.
              '';
          checked =
            loc: def:
            let
              child = def.value;
            in
            def
            // {
              value =
                if isConfiguration child then
                  { name, parent }:
                  let
                    finalized = child { inherit name parent; };
                    declared = typeOfFinalized finalized;
                  in
                  if declared == null || declared == integration then finalized else throw (refusal loc def declared)
                else if child.type == integration then
                  child
                else
                  throw (refusal loc def child.type);
            };
        in
        lib.mkOptionType {
          name = "caissonConfiguration";
          description = "${integration} configuration (what `lib.caisson.${integration}.mkConfiguration` returns)";
          descriptionClass = "noun";
          check = value: isConfiguration value || final.caisson-core.isDeferredConfiguration value;
          merge = loc: defs: lib.mergeOneOption loc (map (checked loc) defs);
        };

      # The option types of the integration `name`, whose modules are of
      # the class `class`, built on the library of nixpkgs in `lib`:
      # `module` (`moduleTypeOf`) and `configuration`
      # (`configurationTypeOf`). `mkIntegration` publishes them as
      # `lib.caisson.<name>.types`, built on the library the
      # integration is composed into.
      typesOf =
        lib:
        { name, class }:
        {
          module = moduleTypeOf lib class;
          configuration = configurationTypeOf lib name;
        };

      # An integration that owns a module class, declared. The
      # declaration carries the entry points as pattern functions,
      # `mkConfiguration` and its `WithEcosystemArgs` variant, and the
      # result holds `namespace`, the value of `lib.caisson.<name>`: the
      # entry points, the registration form `mkModule` bound to the
      # class, the option types `types` (`typesOf`) built from the
      # name and the class, `configurationsModule`, and whatever
      # `extra` adds beside them (variants, and the composition an alt
      # over the class reads). The overlay file writes the namespace under its key,
      # since the output attribute names of an overlay must not depend
      # on `final`:
      #
      #   overlay = final: prev:
      #     let integration = final.caisson.integrations.mkIntegration { ... }; in
      #     { caisson = (prev.caisson or { }) // { nixos = integration.namespace; }; };
      mkIntegration =
        {
          name,
          class,
          mkConfiguration,
          mkConfigurationWithEcosystemArgs,
          # What a configuration of this integration that has no parent
          # returns, as a function of its finalized manifest. When
          # given, the integration has a `mkTopConfiguration`: it takes
          # the arguments of `mkConfiguration`, finalizes the
          # configuration with no parent, and applies this function to
          # the manifest. An integration whose configurations are only
          # declared inside other configurations gives none.
          top ? null,
          extra ? { },
        }:
        let
          mkModule = final.caisson-core.mkModule class;

          mkTopConfiguration = topConfiguration top mkConfiguration;

          # A configuration for every configuration registered in the
          # class (`configs/<class>/<name>`), by its name, each as
          # `mkConfiguration` builds it without `configModule`. The
          # arguments apply to all of them; a flake that wants only some,
          # or a configuration that differs, declares them with
          # `mkConfiguration`.
          # It exists for an integration whose `mkConfiguration` takes
          # `configModule` as optional, which is the mark that it finds
          # the module registered under the configuration's name.
          findsModuleByName = (functionArgs mkConfiguration).configModule or false;
          mkConfigurations = setFunctionArgs (
            args:
            if args ? configModule then
              throw ''
                lib.caisson.${name}.mkConfigurations gives every configuration the
                module registered under its name; pass `configModule` to
                lib.caisson.${name}.mkConfiguration for a configuration that takes
                another.
              ''
            else
              builtins.mapAttrs (_: _: mkConfiguration args) (final.caisson.configs.${class} or { })
          ) (builtins.removeAttrs (functionArgs mkConfiguration) [ "configModule" ]);
        in
        {
          namespace = {
            inherit
              mkConfiguration
              mkConfigurationWithEcosystemArgs
              mkModule
              ;
            types = typesOf final { inherit name class; };
            configurationsModule = configurationsModuleOf name;
          }
          // (if findsModuleByName then { inherit mkConfigurations; } else { })
          // (if top == null then { } else { inherit mkTopConfiguration; })
          // extra;
        };

      # The module of the integration `name` that lets a configuration
      # declare configurations of that integration inside it. It declares
      # `caisson.<name>.configurations`, which takes what
      # `lib.caisson.<name>.mkConfiguration` returns and holds the
      # finished manifest, and `caisson.<name>.exported`, which selects
      # those that are passed up. A configuration learns its name and
      # its parent from where it is declared, so the option finalizes
      # each entry when it is read, with the attribute it is declared
      # under and the manifest of the childless evaluation of the
      # configuration it is declared inside. caisson's
      # core module imports this module for each integration of
      # caisson. An integration written outside caisson registers a
      # module that imports it where its configurations may be declared.
      configurationsModuleOf = name: configurationsModuleFor [ name ];

      # The module that declares the options `configurationsModuleOf`
      # declares, for several integrations at once. The core module of
      # caisson imports it once, for all the integrations of caisson.
      configurationsModuleFor = names: {
        key = "caisson-configurations:${builtins.concatStringsSep "," names}";
        imports = [
          (
            { lib, ... }:
            let
              exported = lib.types.functionTo (lib.types.lazyAttrsOf lib.types.raw);
            in
            {
              options.caisson = genAttrs names (name: configurationsOptionsOf { inherit lib exported; } name);
            }
          )
        ];
      };

      # The options `caisson.<name>.configurations` and
      # `caisson.<name>.exported` of the integration `name`, in a
      # configuration evaluated over the given `lib`. Each entry of
      # `configurations` has the configuration type of the integration
      # (`configurationTypeOf`), built on that `lib`.
      # A library that composes the integration publishes the same type
      # as `lib.caisson.<name>.types.configuration`. The module system
      # builds the type of an option when the value of the option is
      # read, and caisson reads the configurations of an
      # integration only where a module defines them
      # (`integrationsDeclaringIn`). `exported` is the type of
      # `exported`, the same for every integration.
      configurationsOptionsOf =
        { lib, exported }:
        name:
        let
          manifest = lib.caisson-core.evalManifest;
          what = childName: "`caisson.${name}.configurations.${childName}`";
          finalize =
            childName: child:
            let
              # A deferred configuration is held as an entry, finalized
              # when its args are supplied.
              finalized =
                (
                  if lib.caisson-core.isDeferredConfiguration child then
                    lib.caisson-core.deferChild
                  else
                    lib.caisson-core.finalizeChild
                )
                  {
                    name = childName;
                    what = what childName;
                    parent = manifest.childlessManifest;
                  }
                  child;
            in
            if manifest == null then
              throw ''
                ${what childName} is declared in a module evaluation that carries no manifest
                (`lib.caisson-core.evalManifest` is null there), so no
                configuration can be finalized inside it.
              ''
            else if manifest.childless then
              throw ''
                ${what childName} was read in the childless evaluation of the ${manifest.type}
                configuration, whose result the configurations declared inside it read. The childless evaluation
                leaves out the configurations declared inside the ${manifest.type}
                configuration, so `${childName}` has no value there. A configuration
                declared inside it read `${childName}` through its parent, or it read a value of the
                ${manifest.type} configuration whose definition reads `${childName}`.
                Guard such a definition with `!lib.caisson-core.evalManifest.childless`.
                The configurations declared inside it then read the value without that definition.
              ''
            else
              finalized;
        in
        {
          exported = lib.mkOption {
            type = exported;
            default = configurations: configurations;
            defaultText = lib.literalMD "every configuration declared";
            description = ''
              Function that selects which of the ${name} configurations
              declared inside this configuration it passes up. Receives
              `caisson.${name}.configurations` and returns the subset to
              export; `_: { }` exports none. What each selected configuration
              exports is merged into this configuration's `caisson.exports`.
            '';
          };
          exportNote = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "office NixOS configurations take the site prefix; lab NixOS configurations are not deployed from this flake";
            description = ''
              A sentence saying what `caisson.${name}.exported` does to the
              ${name} configurations it passes up, for a selector that does
              more than pass every configuration up unchanged. The caisson top
              records it in the export record (`exportRecord` of the
              manifest it publishes) for each name published from those
              configurations, with the notes of the levels declared inside it.
            '';
          };
          configurations = lib.mkOption {
            type = lib.types.lazyAttrsOf (configurationTypeOf lib name);
            default = { };
            apply = builtins.mapAttrs finalize;
            description = ''
              The ${name} configurations declared inside this
              configuration, by name: each is what
              `lib.caisson.${name}.mkConfiguration` returns, and reads
              back as its manifest, finalized with the name it is declared
              under and this configuration as its parent. A configuration
              declared inside sees this configuration without the configurations declared
              inside it, so a definition that reads one of them is guarded
              with `!lib.caisson-core.evalManifest.childless`.
            '';
          };
        };

      # The integrations whose configurations can be declared inside a
      # configuration: those whose `configurationsModule` its modules
      # import, read from its options. The module declares both
      # `configurations` and `exported`; `caisson.exports` declares
      # `configurations` alone.
      integrationsIn =
        options:
        builtins.filter (
          name:
          let
            declared = options.caisson.${name};
          in
          declared ? configurations && declared ? exported
        ) (builtins.attrNames (options.caisson or { }));

      # Of `integrationsIn options`, the integrations whose
      # `caisson.<integration>.configurations` a module of the configuration
      # defines: those whose highest priority is above the priority of
      # an option default. The others hold no configurations, so neither
      # their configurations nor their `exported` selector is read, which
      # spares merging those options in every configuration for every
      # integration the configuration could hold.
      integrationsDeclaringIn =
        options:
        builtins.filter (name: options.caisson.${name}.configurations.highestPrio < 1500) (
          integrationsIn options
        );

      # The configurations declared inside an evaluated configuration,
      # by integration and then name, as the `children` an
      # integration's `evaluate` returns: the values of its
      # `caisson.<integration>.configurations` options, which finalize
      # each entry when read. An integration with none declared is left
      # out.
      childrenOf =
        { options, config }:
        filterAttrs (_: declared: declared != { }) (
          genAttrs (integrationsDeclaringIn options) (name: config.caisson.${name}.configurations)
        );

      # True when `entry`, an entry of `caisson.exports.configurations`
      # of a configuration, belongs to that configuration as a reader of
      # the configurations of the integration `type`: no configuration
      # of `type` sits between the two, so the nearest configuration
      # above the entry that a reader of `type` stops at is that
      # configuration. The path of the entry runs from the children of that
      # configuration down to the entry, so the entry belongs to it
      # when no segment of the path before the last is of `type`.
      # Segments of other integrations and systems do not count. A
      # colmena configuration builds its nodes from the NixOS
      # configurations that belong to it in this sense:
      # `belongsHere "nixos"` keeps a NixOS configuration declared inside a disk layout or a
      # structural group and leaves out a NixOS configuration declared
      # inside a node.
      belongsHere = type: entry: !(builtins.any (segment: segment.type == type) (init entry.path));

      # The nearest configuration above `manifest` whose integration is
      # one of `types`, null when there is none. The manifest records
      # the nearest ancestor of each integration; of those, the nearest
      # is the ancestor with the most ancestors itself. A home-manager
      # configuration reads the NixOS or nix-darwin configuration it is
      # declared inside this way.
      nearestOf =
        types: manifest:
        builtins.foldl' (
          found: type:
          let
            candidate = (manifest.nearest or { }).${type} or null;
          in
          if candidate == null then
            found
          else if found == null || builtins.length candidate.ancestors > builtins.length found.ancestors then
            candidate
          else
            found
        ) null types;

      # The nearest configuration above `manifest` that has an
      # activation (`mkModuleConfiguration`'s `activation`), as its
      # childless manifest, or null when there is none. A home-manager
      # configuration inside a NixOS configuration finds the NixOS
      # configuration; an nvf
      # configuration inside that home-manager configuration finds the
      # home-manager configuration.
      activatingAncestorOf =
        manifest:
        let
          found = builtins.filter (ancestor: (ancestor.activation or null) != null) (
            manifest.ancestors or [ ]
          );
        in
        if found == [ ] then null else last found;

      # The `activation` of a NixOS, nix-darwin or system-manager
      # configuration. Its identity is its system, `toplevel`, null for
      # a configuration that builds none, as the nixos-minimal
      # integration can produce. Its marker is a file under `/etc`,
      # which the module `activation-marker` of its class writes.
      #
      # Such a configuration is activated on the computer it describes.
      # A NixOS configuration declared inside another, such as an image,
      # is applied on a different computer than the configuration above,
      # and the marker under `/etc` that it finds there is the marker it
      # wrote, so it checks nothing above it: `standsAlone`.
      machineActivation = {
        standsAlone = true;
        identity =
          manifest: if (manifest.outputs or { }) ? toplevel then manifest.outputs.toplevel.outPath else null;
        marker = _manifest: "/etc/caisson/marker.json";
      };

      # The file name of the marker of a configuration activated for a
      # user: the integration and the name the configuration is declared
      # under, with the characters the shell would read inside double
      # quotes, and the path separator, replaced.
      markerFileName =
        manifest:
        "${manifest.type}-${
          builtins.replaceStrings [ "/" "\"" "$" "`" "\\" ] [ "_" "_" "_" "_" "_" ] (
            manifest.name or "default"
          )
        }.json";

      # The digest a marker holds for an identity: the SHA-256 of its
      # store path. Computing the store path runs the childless
      # evaluation and builds nothing, and the digest refers to no store
      # path, so a marker that holds it depends on nothing. The digest
      # is compared and not read as a path.
      digestOf = identity: builtins.hashString "sha256" identity;

      # What the activation of the configuration of `manifest` writes
      # into its marker: the digest of the identity in the result of its
      # childless evaluation (`digestOf`). `path` is the shell text of the path of
      # the marker. Null when the configuration has no activation or no
      # identity.
      markerOf =
        manifest:
        let
          activation = manifest.activation or null;
          childless = manifest.childlessManifest or manifest;
          identity = if activation == null then null else activation.identity childless;
        in
        if identity == null then
          null
        else
          {
            path = activation.marker childless;
            identity = digestOf identity;
            text = builtins.toJSON { identity = digestOf identity; };
          };

      # The profiles of the configuration of `manifest` that a switch of
      # the NixOS or nix-darwin configuration above sets,
      # `setBy = "machine"` in its profile adapter (`profileAdapter` of
      # `activation`), by profile name. Each is the digest of the store
      # path the profile holds once the configuration is applied
      # (`digestOf`). The marker of the configuration above records
      # these digests for each configuration whose profiles it sets, and
      # the drift check of the configuration compares them
      # (`driftCheckOf`). Empty for a configuration without a profile
      # adapter, or whose profiles the configuration above does not set.
      machineProfilesOf =
        manifest:
        let
          adapter = (manifest.activation or { }).profileAdapter or null;
          profiles = if adapter == null then { } else (adapter manifest).profiles;
        in
        builtins.mapAttrs (_: profile: digestOf (toString profile.holds)) (
          final.filterAttrs (_: profile: profile.setBy == "machine") profiles
        );

      # True when `entry`, an entry of `caisson.exports.configurations`
      # of the configuration of `manifest`, checks the marker of that
      # configuration when it is activated: the entry has an activation,
      # and the configuration is the nearest one above it that has an
      # activation.
      checksMarkerOf =
        manifest: entry:
        let
          ancestor = activatingAncestorOf entry.manifest;
        in
        (entry.manifest.activation or null) != null
        && !(entry.manifest.activation.standsAlone or false)
        && ancestor != null
        && placeOf ancestor == placeOf manifest;

      # Where a configuration is in the tree of configurations: the integration and the name
      # of each configuration from the caisson top down to it, the nodes of the
      # systems included. Configurations at the same depth have
      # different places, such as a home-manager configuration and a
      # hjem configuration inside the same NixOS configuration, and the
      # manifests of the childless and the full evaluation of a
      # configuration have the same place.
      placeOf =
        manifest:
        builtins.map (node: "${node.type or "lib"}/${toString (node.name or "")}") (
          (manifest.ancestors or [ ]) ++ [ manifest ]
        );

      # The shell text with which the activation of the configuration of
      # `manifest` checks for drift: it compares the marker of the
      # nearest configuration above with an activation against the
      # identity of that configuration as this configuration was built
      # for it, and prints a warning to standard error when the marker is
      # missing or names another identity. It does not stop the
      # activation. When that configuration activates this configuration, its
      # marker already belongs to the generation being activated, and
      # the check prints nothing. Empty when there is no such
      # configuration, or it has no identity. `jq` is the path of a jq
      # executable, and `optionText` names the option that turns the
      # warning off, for the message.
      #
      # `profiles` are the profiles of this configuration that a switch
      # of the configuration above sets (`machineProfilesOf`). The
      # identity of the configuration above leaves out the
      # configurations declared inside it, so it is the same when this
      # configuration changes. For each such profile, the check also
      # compares the digest that the marker of the configuration above
      # records for this configuration with the digest of what the
      # profile holds in this configuration, and prints a warning when
      # they differ: then this configuration was built from another
      # version than the switch applied, and the profile holds what the
      # switch applied.
      driftCheckOf =
        {
          jq,
          optionText,
          profiles ? { },
        }:
        manifest:
        let
          ancestor =
            if (manifest.activation.standsAlone or false) then null else activatingAncestorOf manifest;
          expected = if ancestor == null then null else ancestor.activation.identity ancestor;
          marker = ancestor.activation.marker ancestor;
          above = "the ${ancestor.type} configuration `${ancestor.name or "(unnamed)"}`";
          self = "the ${manifest.type} configuration `${manifest.name or "(unnamed)"}`";
          # The digest of the identity, quoted for the shell. A digest is
          # hexadecimal, so quoting it whole is enough.
          escaped = "'${digestOf expected}'";
          # A line of the warning, quoted for the shell as it is. The
          # names in it are in backticks, which the shell would run
          # inside double quotes.
          say = text: "echo ${final.escapeShellArg text} >&2";
          # The name under which the marker of the configuration above records the
          # profiles of this configuration.
          key = markerFileName manifest;
          profileCheck = name: digest: ''
            _caissonProfile="$(${jq} -r --arg key ${final.escapeShellArg key} --arg name ${final.escapeShellArg name} '.profiles[$key][$name] // empty' < "$_caissonMarker")"
            if [ "$_caissonProfile" != '${digest}' ]; then
              ${say "WARNING: the `${name}` profile of ${self}, which ${above} sets, holds another version than this configuration was built with."}
              ${say "  digest of what ${above} put in the profile:"}
              echo "    ''${_caissonProfile:-unknown}" >&2
              ${say "  digest of what this configuration puts in the profile:"}
              echo "    ${digest}" >&2
              ${say "  Activate ${above} with this version of ${self},"}
              ${say "  or set ${optionText} to false in ${self}."}
            fi
          '';
          # The checks of the profiles, each on separate lines after the
          # check of the identity. A configuration without such profiles
          # gets no text here.
          profileChecks = final.concatStrings (
            final.mapAttrsToList (name: digest: "\n" + profileCheck name digest) profiles
          );
        in
        if expected == null then
          ""
        else
          ''
            _caissonMarker="${marker}"
            if [ ! -f "$_caissonMarker" ]; then
              echo "WARNING: $_caissonMarker does not exist." >&2
              ${say "  ${self} is declared inside ${above},"}
              ${say "  and the activation of ${above} has not recorded what it applied."}
              ${say "  Activate ${above} as this configuration was built with it,"}
              ${say "  or set ${optionText} to false in ${self}."}
            else
              _caissonApplied="$(${jq} -r '.identity // empty' < "$_caissonMarker")"
              if [ "$_caissonApplied" != ${escaped} ]; then
                ${say "WARNING: ${self} was built for a version of ${above} that differs from the version that is applied."}
                ${say "  digest of the version applied (configurations declared inside it left out):"}
                echo "    ''${_caissonApplied:-unknown}" >&2
                ${say "  digest of the version built for (configurations declared inside it left out):"}
                echo "    "${escaped} >&2
                ${say "  Activate ${above} as this configuration was built with it,"}
                ${say "  or set ${optionText} to false in ${self}."}
              fi${profileChecks}
            fi
          '';

      # A name a configuration is declared under, with the characters
      # the shell would read inside double quotes, and the path
      # separator, replaced, for use in a path.
      safeName =
        name:
        builtins.replaceStrings [ "/" "\"" "$" "`" "\\" ] [ "_" "_" "_" "_" "_" ] (
          if name == null then "default" else name
        );

      # A configuration that is a program a person runs, such as a
      # Neovim, kept in a separate Nix profile, the way a home-manager
      # configuration keeps its generations in the home-manager profile.
      #
      # `activationPackage` holds `activate`, which checks for drift
      # against the nearest configuration above with an activation
      # (`driftCheckOf`, when `warn`), and points the profile at
      # `package` with `nix-env --profile`, which also makes the
      # profile a garbage-collector root. When the profile already
      # points at `package`, it changes nothing, so activating the same
      # generation again adds no generation to the profile.
      #
      # Where the profile is depends on the configuration above. Inside
      # a NixOS, nix-darwin or system-manager configuration it is a
      # profile of the system, `/nix/var/nix/profiles/caisson/<kind>/<name>`,
      # which that configuration activates as root. Inside a home-manager configuration or a hjem
      # configuration, or as a caisson top, it is a profile of the user,
      # `$HOME/.local/state/caisson/profiles/<kind>/<name>`. The path
      # names `$HOME` and not `$XDG_STATE_HOME`: the units of a NixOS
      # configuration run without `$XDG_STATE_HOME`, and a shell may set it, and the
      # profile must be the same file for both. The
      # configuration above activates it each time it is activated
      # itself, so activating the configuration above puts the profile
      # back to what that configuration declares.
      #
      # `profile` is what the configuration above reads from the
      # manifest: the shell text of the path of the profile, whether it
      # is a profile of the system or of the user, the `package` the
      # profile points at, the `programs` the
      # package has in `bin`, and `variable`, the name of the variable a
      # shell sets to choose which profile of this sort it runs
      # (`profileShimsOf`).
      profileOf =
        {
          pkgs,
          manifest,
          kind,
          package,
          programs,
          variable,
          warn ? true,
        }:
        let
          ancestor = activatingAncestorOf manifest;
          ofSystem = ancestor != null && (ancestor.activation.standsAlone or false);
          name = safeName (manifest.name or null);
          path =
            if ofSystem then
              "/nix/var/nix/profiles/caisson/${kind}/${name}"
            else
              "$HOME/.local/state/caisson/profiles/${kind}/${name}";
          check =
            if warn then
              driftCheckOf {
                jq = "${pkgs.jq}/bin/jq";
                optionText = "`caisson.drift.warn`";
              } manifest
            else
              "";
        in
        {
          activationPackage = pkgs.writeTextFile {
            name = "${kind}-${name}-activation";
            destination = "/activate";
            executable = true;
            text = ''
              #!${pkgs.runtimeShell}
              set -eu
              ${check}
              profile="${path}"
              ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$profile")"
              if [ "$(${pkgs.coreutils}/bin/readlink -f "$profile" 2>/dev/null || true)" != '${package}' ]; then
                ${pkgs.nix}/bin/nix-env --profile "$profile" --set '${package}'
              fi
            '';
          };
          profile = {
            inherit
              path
              programs
              variable
              kind
              name
              package
              ;
            scope = if ofSystem then "system" else "user";
          };
        };

      # The entries of `caisson.exports.configurations` of the
      # configuration of `manifest` that it activates as profiles
      # (`profileOf`): those with a `profile`, evaluated for the system
      # of the configuration, whose nearest configuration above with an
      # activation is this configuration. A profile inside a home-manager
      # configuration inside this configuration is activated by that
      # home-manager configuration, and is left out.
      profilesActivatedBy =
        manifest: configurations:
        builtins.filter (
          entry:
          (entry.manifest.outputs or { }) ? profile
          && (entry.manifest.system or null) == (manifest.system or null)
          && checksMarkerOf manifest entry
        ) configurations;

      # For each variable the profiles in `entries` are chosen with, the
      # profile a configuration runs when a shell sets no other, and the
      # programs of all of them. The profile is the profile `selected` names
      # for the variable, as `<kind>/<name>`, or the only profile for it. `what`
      # names the configuration, for the message when several profiles
      # share a variable and `selected` names none of them.
      profileChoicesOf =
        { selected, what }:
        entries:
        let
          variables = unique (builtins.map (entry: entry.manifest.outputs.profile.variable) entries);
          choiceOf =
            variable:
            let
              sharing = builtins.filter (entry: entry.manifest.outputs.profile.variable == variable) entries;
              nameOf = entry: "${entry.manifest.outputs.profile.kind}/${entry.manifest.outputs.profile.name}";
              named = builtins.filter (entry: nameOf entry == selected.${variable}) sharing;
              chosen =
                if selected ? ${variable} then
                  if named != [ ] then
                    builtins.head named
                  else
                    throw "caisson: ${what} selects `${selected.${variable}}` with `caisson.profiles.selected.${variable}`, and its profiles for that variable are ${builtins.concatStringsSep ", " (builtins.map nameOf sharing)}."
                else if builtins.length sharing == 1 then
                  builtins.head sharing
                else
                  throw "caisson: ${what} activates several profiles chosen with `${variable}` (${builtins.concatStringsSep ", " (builtins.map nameOf sharing)}). Set `caisson.profiles.selected.${variable}` to the profile a shell runs when it sets no other.";
            in
            {
              inherit chosen;
              programs = unique (builtins.concatMap (entry: entry.manifest.outputs.profile.programs) sharing);
            };
        in
        genAttrs variables choiceOf;

      # The programs with which a configuration that activates profiles
      # (`profileOf`) lets a shell choose among them: for each program,
      # an executable of that name that runs the program of the profile
      # the variable names, read each time it runs, and of `fallback`
      # when the variable is unset. A configuration sets the variable to
      # its default, a configuration declared inside it sets it to its
      # own, and a shell can `export` another. `fallback` is shell text,
      # which may name variables such as `$HOME`.
      profileShimsOf =
        {
          pkgs,
          variable,
          programs,
          fallback,
        }:
        pkgs.runCommand "caisson-profile-shims-${variable}" { } (
          ''
            mkdir -p "$out/bin"
          ''
          + builtins.concatStringsSep "" (
            builtins.map (program: ''
              cat > "$out/bin/${program}" <<'EOF'
              #!${pkgs.runtimeShell}
              exec "''${${variable}:-${fallback}}/bin/${program}" "$@"
              EOF
              chmod +x "$out/bin/${program}"
            '') programs
          )
        );

      isManifest = value: builtins.isAttrs value && (value._type or null) == "caisson-manifest";

      # How a configuration is published: the exports its manifest
      # records in `exportsTo`, as a list, empty for a configuration
      # that is not published under a name (structural, flake-parts).
      # An integration may give one export or a list of them; an export
      # with `only` applies to the configurations whose manifest it
      # holds true for. The entry of a deferred configuration
      # (`caisson-core.deferChild`) is published in the same way, from
      # the `exportsTo` its `record` holds: `value` and `only` receive
      # the entry, which holds its name, type, class and parent.
      exportsOf =
        manifest:
        let
          recorded = manifest.exportsTo or null;
          all =
            if recorded == null then
              [ ]
            else if builtins.isList recorded then
              recorded
            else
              [ recorded ];
        in
        builtins.filter (exportsTo: (exportsTo.only or (_: true)) manifest) all;

      showPath =
        path:
        builtins.concatStringsSep " / " (builtins.map (segment: "${segment.type} ${segment.name}") path);

      # A position as the export record holds it: the file and the
      # line number (`line`) of what `builtins.unsafeGetAttrPos` returns, null
      # when it returns none.
      positionOf = position: if position == null then null else { inherit (position) file line; };

      # The positions of the definitions of the entry `name` of
      # `option`, an option of a configuration whose value is an
      # attribute set, as the record writes code: for each definition that defines
      # the entry, the file and the line number where the definition
      # writes the name. A definition that carries no position for the
      # name, because a function built the attribute set, has the file
      # the module system records for it and a `line` of null.
      definitionCodeOf =
        option: name:
        builtins.concatMap (
          definition:
          if builtins.isAttrs definition.value && definition.value ? ${name} then
            let
              position = builtins.unsafeGetAttrPos name definition.value;
            in
            [
              (
                if position == null then
                  {
                    file = inSource definition.file;
                    line = null;
                  }
                else
                  {
                    file = inSource position.file;
                    inherit (position) line;
                  }
              )
            ]
          else
            [ ]
        ) option.definitionsWithLocations;

      # Code positions as a message writes them.
      showCode =
        code:
        builtins.concatStringsSep ", " (
          builtins.map (
            position:
            if position.line == null then position.file else "${position.file}:${toString position.line}"
          ) code
        );

      # The checks the modules of a configuration declare in `caisson.checks`, by name,
      # from the option and its value: each entry with its
      # `derivation`, null for an annotation, `category`,
      # `description`, `enable`, `top`, the test caisson top whose
      # checks the entry declares, and `code`, the positions of the
      # definitions of the entry (`definitionCodeOf`).
      checkDeclarationsOf =
        { option, value }:
        builtins.mapAttrs (name: entry: {
          inherit (entry)
            derivation
            category
            description
            enable
            top
            ;
          code = definitionCodeOf option name;
        }) value;

      # The positions of the definitions that declare the
      # configurations inside a configuration, from its options: by
      # integration and then the name a configuration is declared
      # under, the positions `definitionCodeOf` gives for that name in
      # `caisson.<integration>.configurations`. Reading the definitions
      # finalizes no configuration, so the childless evaluation records
      # them too, and the configurations declared inside read them
      # there.
      childrenCodeOf =
        options:
        genAttrs (integrationsDeclaringIn options) (
          integration:
          let
            option = options.caisson.${integration}.configurations;
            names = unique (
              builtins.concatMap (
                definition: if builtins.isAttrs definition.value then builtins.attrNames definition.value else [ ]
              ) option.definitionsWithLocations
            );
          in
          genAttrs names (definitionCodeOf option)
        );

      # The registry entries a module evaluation evaluated, with the
      # options under `caisson` that each entry defines.
      #
      # A registry entry that defines an option under `caisson`, such as
      # `caisson.forChildren.systems`, depends on the module that
      # declares the option. Most of these options are declared by the
      # framework module of the class, `closure-lib.caisson.modules.<class>.core`.
      # caisson imports the framework module into every evaluation it
      # makes, so a missing import changes nothing there. A consumer
      # who evaluates the entry outside caisson, with
      # `nixpkgs.lib.nixosSystem` over the `nixosModules` output of a
      # flake, gets no framework module, and the definition fails as a
      # definition of an option that no module declares. An entry
      # declares that dependence by importing the module that declares
      # the option.
      #
      # `graph` is the import graph `lib.evalModules` returns: for each
      # module, its `key`, its `file`, whether it is `disabled`, and the
      # modules it imports. `options` are the options of the evaluation.
      # A registry entry is a module whose key is
      # `modules.<class>.<name>@<project>` (`keyedModules`). The files
      # of an entry are the files of the entry and of every module it
      # imports, at any depth. The result holds each entry by registry
      # key, with `project`, `file`, and `defines`: for each option
      # under `caisson` that a file of the entry defines, the option
      # as `option`, the files of the entry that define it as `files`,
      # the files that declare it as `declarations`, and `declared`,
      # true when a file of the entry declares it. A
      # module the graph reaches under several paths is read at its
      # first occurrence.
      registryEntriesOf =
        { graph, options }:
        let
          isOption = value: builtins.isAttrs value && (value._type or null) == "option";
          optionsUnder =
            value:
            if isOption value then
              [ value ]
            else if builtins.isAttrs value then
              builtins.concatMap optionsUnder (builtins.attrValues value)
            else
              [ ];
          caissonOptions = optionsUnder (options.caisson or { });
          enabled = builtins.filter (node: !(node.disabled or false));
          filesOf = node: [ node.file ] ++ builtins.concatMap filesOf (enabled node.imports);
          entriesIn =
            nodes:
            builtins.concatMap (
              node:
              (if builtins.substring 0 8 (toString (node.key or "")) == "modules." then [ node ] else [ ])
              ++ entriesIn (enabled node.imports)
            ) (enabled nodes);
          entryOf =
            node:
            let
              # The registry wraps the module of an entry in modules that
              # each import the next module alone. A wrapper names no
              # file, so the module system gives it the file of the
              # module that imports the entry, such as the file of the
              # configuration that selects it. The module of the entry is
              # the first module below the wrappers whose file differs
              # from the file of the wrappers, and the files of the entry
              # are the files of that module and of every module it
              # imports.
              below =
                wrapper:
                let
                  imported = enabled wrapper.imports;
                in
                if builtins.length imported != 1 then
                  wrapper
                else if (builtins.head imported).file == node.file then
                  below (builtins.head imported)
                else
                  builtins.head imported;
              module = below node;
              inherit (module) file;
              files = unique (filesOf module);
              inEntry = file: builtins.elem file files;
              defined = builtins.filter (option: builtins.any inEntry option.files) caissonOptions;
              registered = registryPartsOf node.key;
            in
            {
              name = registered.key;
              value = {
                inherit (registered) project;
                file = inSource file;
                defines = builtins.map (option: {
                  option = builtins.concatStringsSep "." option.loc;
                  files = builtins.map inSource (builtins.filter inEntry option.files);
                  declarations = builtins.map inSource option.declarations;
                  declared = builtins.any inEntry option.declarations;
                }) defined;
              };
            };
        in
        builtins.listToAttrs (builtins.map entryOf (entriesIn graph));

      # The check `registries` of a caisson top for `system`, by name,
      # the default check every caisson top carries.
      #
      # It checks that every registry entry that defines an option under
      # `caisson` imports a module that declares that option
      # (`registryEntriesOf`). The entries it reads are those that the
      # evaluation results gathered at the caisson top evaluated
      # (`checkNodesOf`), each evaluation result that is for `system`
      # or for no system. Its category is `eval`: the derivation builds
      # nothing, and its build fails, printing the entries and the
      # options, when any entry defines an option that it imports no
      # declaration of. The derivation runs `/bin/sh`, so it needs no
      # package set.
      registriesCheckOf =
        { manifest, system }:
        let
          nodes = builtins.filter (
            node:
            let
              nodeSystem =
                let
                  above = builtins.filter (ancestor: ancestor ? system) (node.manifest.ancestors or [ ]);
                in
                if node.manifest ? system then
                  node.manifest.system
                else if above == [ ] then
                  null
                else
                  (last above).system;
            in
            nodeSystem == null || nodeSystem == system
          ) (checkNodesOf manifest);
          missing = builtins.concatMap (
            node:
            let
              entries = node.manifest.registryEntries or null;
            in
            if entries == null then
              [ ]
            else
              builtins.concatMap (
                key:
                let
                  entry = entries.${key};
                  undeclared = builtins.filter (definition: !definition.declared) entry.defines;
                in
                if undeclared == [ ] then
                  [ ]
                else
                  [
                    {
                      inherit key entry undeclared;
                      inherit (node) namePath;
                    }
                  ]
              ) (builtins.attrNames entries)
          ) nodes;
          # Each entry is reported for the first evaluation result that
          # evaluated it.
          firstOf = builtins.foldl' (
            seen: found: if seen ? ${found.key} then seen else seen // { ${found.key} = found; }
          ) { } missing;
          showFound =
            found:
            let
              project = if found.entry.project == null then "" else " of the project `${found.entry.project}`";
            in
            ''
              `${found.key}`${project}, file ${found.entry.file}, evaluated in ${showNamePath found.namePath}:
              ${builtins.concatStringsSep "\n" (
                builtins.map (
                  definition:
                  "  defines `${definition.option}` in ${builtins.concatStringsSep ", " definition.files}, declared in ${builtins.concatStringsSep ", " definition.declarations}"
                ) found.undeclared
              )}'';
          message = ''
            caisson: these registry entries define options under `caisson` and import no
            module that declares them:

            ${builtins.concatStringsSep "\n" (builtins.map showFound (builtins.attrValues firstOf))}

            caisson imports the framework module of the class into every evaluation it
            makes, so the definitions work inside caisson. A configuration evaluated outside
            caisson, such as a NixOS configuration built with `nixpkgs.lib.nixosSystem` from
            the `nixosModules` output of this flake, does not import it, and each of these
            definitions fails there as a definition of an undeclared option. Import the
            module that declares each option into the entry. Most of these options are
            declared by the core module of caisson for the class, the registry entry
            `core` of the class, which a flake that lists caisson in `projects` reads as
            `closure-lib.caisson.modules.<class>."caisson/core"`.
          '';
          passes = firstOf == { };
          position = positionOf (builtins.unsafeGetAttrPos "registries" declared);
          declared = {
            registries = {
              derivation = builtins.derivation {
                name = "registries";
                inherit system;
                builder = "/bin/sh";
                args = [
                  "-c"
                  (if passes then "echo pass > $out" else "printf '%s\\n' \"$message\" >&2; exit 1")
                ];
                message = if passes then "" else message;
              };
              category = "eval";
              description = "every registry entry that defines an option under `caisson` imports a module that declares it";
              # The position of the attribute `registries` in this file.
              code = if position == null then [ ] else [ (position // { file = inSource position.file; }) ];
            };
          };
        in
        declared;

      # The checks a configuration records for a system, by name: the
      # default checks for that system and the checks its modules
      # declare for that system (`checkDeclarationsOf`). `what` names
      # the configuration in the messages, `type` its integration, and
      # `defaults` are the default checks by name, each
      # `{ derivation; category; description; code; }`, where `code`
      # holds the positions that declare the default check.
      #
      # A declaration with a `derivation` declares a check, and it
      # names its category. A declaration without a `derivation`
      # annotates the default check of the same name: its `category`
      # and `description` replace those of the default where they are
      # given, and its `enable` is the `enable` of the check. A
      # declaration with a `derivation` under the name of a default
      # check, a declaration without a `derivation` that has no default check to
      # annotate, and a check with no category are refused, each when
      # its entry is read.
      #
      # A declaration with a `top` declares the checks of a test caisson
      # top for `system`, the system of the evaluation result
      # (`topChecksOf`). Each recorded check carries `top`, null for a
      # check that no such declaration declares.
      checksOfConfiguration =
        {
          what,
          type,
          system,
          defaults,
        }:
        allDeclarations:
        let
          fromTops = filterAttrs (_: declaration: (declaration.top or null) != null) allDeclarations;
          declarations = builtins.removeAttrs allDeclarations (builtins.attrNames fromTops);
          entryOf =
            name:
            let
              default = defaults.${name} or null;
              declaration = declarations.${name} or null;
              option = "`caisson.checks.${name}` of ${what}, defined at ${showCode declaration.code},";
            in
            if default == null then
              if declaration.derivation == null then
                throw ''
                  caisson: ${option} annotates the check `${name}`, and the configuration
                  has no check of that name: the ${type} integration declares no default
                  check `${name}`${
                    if type == "flake-parts" then ", and no module defines `checks.${name}` for the system" else ""
                  }. Give the entry a `derivation` and a `category` to declare a check.
                ''
              else if declaration.category == null then
                throw ''
                  caisson: ${option} declares a check and names no `category`. Name a
                  category declared in `caisson.checkCategories`, such as `build` or `eval`.
                ''
              else
                declaration // { top = null; }
            else if declaration == null then
              {
                inherit (default)
                  derivation
                  category
                  description
                  code
                  ;
                enable = true;
                top = null;
              }
            else if declaration.derivation != null then
              throw ''
                caisson: ${option} sets a `derivation`, and the ${type} integration declares a
                default check named `${name}`. Declare the check under another name, or
                leave `derivation` out to annotate the default check.
              ''
            else
              {
                inherit (default) derivation;
                category = if declaration.category != null then declaration.category else default.category;
                description =
                  if declaration.description != null then declaration.description else default.description;
                inherit (declaration) enable;
                code = default.code ++ declaration.code;
                top = null;
              };
          declared = genAttrs (unique (
            builtins.attrNames defaults ++ builtins.attrNames declarations
          )) entryOf;
          fromTop = builtins.foldl' (
            gathered: name:
            let
              checks = topChecksOf {
                inherit
                  what
                  type
                  system
                  defaults
                  name
                  ;
                declaration = fromTops.${name};
              };
              clashing = builtins.filter (checkName: declared ? ${checkName} || gathered ? ${checkName}) (
                builtins.attrNames checks
              );
            in
            if clashing == [ ] then
              gathered // checks
            else
              throw ''
                caisson: `caisson.checks.${name}` of ${what}, defined at ${showCode fromTops.${name}.code},
                declares the check `${builtins.head clashing}` of its test caisson top, and the
                configuration declares another check of that name. Rename the entry or the check.
              ''
          ) { } (builtins.attrNames fromTops);
        in
        declared // fromTop;

      # The checks that the declaration `name` with a `top` declares for
      # `system`, by name: for each check of `top.checks.<system>`, the
      # test caisson top, an entry named `<name>-<check>`. Its category
      # and description are those of the declaration where it gives
      # them, then those of the check record of the test caisson top
      # (`caisson.manifest.checkRecord`) where it is a caisson top, and
      # the category is `build` where neither gives a category. `top` holds
      # `name`, the name of the declaration, `check`, the name of the
      # check in the test caisson top, and `record`, the entry of its
      # check record, null for a test caisson top that publishes none. A
      # declaration with a `top` that also sets a `derivation`, or that
      # has the name of a default check of the integration, is refused.
      topChecksOf =
        {
          what,
          type,
          system,
          defaults,
          name,
          declaration,
        }:
        let
          option = "`caisson.checks.${name}` of ${what}, defined at ${showCode declaration.code},";
          top = declaration.top;
          published = (top.checks or { }).${system} or { };
          manifest = (top.caisson or { }).manifest or null;
          records = if builtins.isAttrs manifest then (manifest.checkRecord or { }).${system} or { } else { };
          entryFor =
            check: derivation:
            let
              record = records.${check} or null;
              fromRecord = field: if record == null then null else record.${field} or null;
              category =
                if declaration.category != null then
                  declaration.category
                else if fromRecord "category" != null then
                  fromRecord "category"
                else
                  "build";
            in
            {
              name = "${name}-${check}";
              value = {
                inherit derivation category;
                description =
                  if declaration.description != null then declaration.description else fromRecord "description";
                inherit (declaration) enable code;
                top = {
                  inherit name check record;
                };
              };
            };
        in
        if declaration.derivation != null then
          throw ''
            caisson: ${option} sets both a `derivation` and a `top`. An entry with a
            `top` declares the checks of that caisson top; declare a single check in a
            separate entry.
          ''
        else if defaults ? ${name} then
          throw ''
            caisson: ${option} sets a `top`, and the ${type} integration declares a
            default check named `${name}`. Declare the test caisson top under another name.
          ''
        else
          builtins.listToAttrs (builtins.attrValues (builtins.mapAttrs entryFor published));

      # The categories of checks that `declarations` declare, a list of
      # attribute sets of categories by name, each
      # `{ description; volatile; code; }`, merged into a single
      # attribute set. A name that several declarations declare has the same `description` and
      # `volatile` in each declaration, and it carries the positions of
      # all of them; a name declared with different properties is
      # refused when its entry is read.
      categoriesUnion = builtins.foldl' (
        merged: declared:
        merged
        // builtins.mapAttrs (
          name: category:
          let
            seen = merged.${name} or null;
            show =
              entry:
              "description ${builtins.toJSON entry.description}, volatile ${
                if entry.volatile then "true" else "false"
              }, at ${showCode entry.code}";
          in
          if seen == null then
            category
          else if seen.description == category.description && seen.volatile == category.volatile then
            seen // { code = unique (seen.code ++ category.code); }
          else
            throw ''
              caisson: the check category `${name}` is declared with different properties:
                ${show seen}
                ${show category}
              A category has the same description and volatility wherever it is declared.
            ''
        ) declared
      ) { };

      # A path by the names configurations are declared under, as an
      # address under the `children` of the manifests from where it
      # starts.
      showNamePath =
        namePath:
        if namePath == [ ] then
          "the caisson top"
        else
          builtins.concatStringsSep "." (
            builtins.map (segment: "children.${segment.type}.${segment.name}") namePath
          );

      # The configurations declared directly inside the configuration
      # of `manifest` whose checks are gathered: its children, those
      # evaluated per system inside their systems included, each with
      # the name it is declared under and its path from `manifest`. The
      # entry of a deferred configuration is left out, since nothing
      # inside it is evaluated before its args are given, and so is a
      # package config, whose sets are not checks.
      checkChildrenOf =
        manifest:
        let
          children = manifest.children or { };
          segment = type: name: { inherit type name; };
          direct = builtins.concatMap (
            integration:
            builtins.map (name: {
              inherit name;
              manifest = children.${integration}.${name};
              namePath = [ (segment integration name) ];
            }) (builtins.attrNames children.${integration})
          ) (builtins.filter (integration: integration != "system") (builtins.attrNames children));
          bySystem = builtins.concatMap (
            system:
            let
              node = children.system.${system};
            in
            builtins.concatMap (
              integration:
              builtins.map (name: {
                inherit name;
                manifest = node.children.${integration}.${name};
                namePath = [
                  (segment "system" system)
                  (segment integration name)
                ];
              }) (builtins.attrNames node.children.${integration})
            ) (builtins.attrNames (node.children or { }))
          ) (builtins.attrNames (children.system or { }));
        in
        builtins.filter (child: isManifest child.manifest && child.manifest.type != "nixpkgs") (
          direct ++ bySystem
        );

      # The configurations whose checks a configuration gathers: the
      # configuration of `manifest` and every configuration declared
      # inside it, at any depth, whatever the `exported` selectors pass
      # up. Each comes with `namePath`, its path from `manifest` by the
      # names it is declared under, and `parts`, the names its checks
      # are published under: the names on that path, without the
      # systems and without the names of flake-parts configurations,
      # whose checks are keyed by name already.
      checkNodesOf =
        manifest:
        [
          {
            inherit manifest;
            namePath = [ ];
            parts = [ ];
          }
        ]
        ++ builtins.concatMap (
          child:
          builtins.map (
            node:
            node
            // {
              namePath = child.namePath ++ node.namePath;
              parts = (if child.manifest.type == "flake-parts" then [ ] else [ child.name ]) ++ node.parts;
            }
          ) (checkNodesOf child.manifest)
        ) (checkChildrenOf manifest);

      # The checks gathered at the configuration of `manifest`, by
      # system and then published name: the checks with `enable` that
      # it and the configurations inside it record (`checkNodesOf`).
      # The published name of a check is the names of the
      # configurations from here down to the configuration that
      # declares it, joined with `-`, then the name of the check: the
      # check `toplevel` of the NixOS configuration `nas-1` declared
      # here is `nas-1-toplevel`. The names of flake-parts
      # configurations are left out of it. Each entry holds the check as
      # the manifest records it, its name there as `checkName`, its
      # `namePath`, and `volatile`, from its category.
      #
      # The categories are those the configurations declare, together
      # (`categoriesUnion`). A check whose category none of them declares
      # is refused when it is read, and so is a stage declared inside
      # the configuration, and checks that share a published name for
      # a system.
      gatheredChecksOf =
        manifest:
        let
          nodes = checkNodesOf manifest;
          staged = builtins.filter (
            node: node.namePath != [ ] && (node.manifest.checkStages or { }) != { }
          ) nodes;
          categories = categoriesUnion (builtins.map (node: node.manifest.checkCategories or { }) nodes);
          systems = unique (
            builtins.concatMap (node: builtins.attrNames (node.manifest.checks or { })) nodes
          );
          entries = builtins.concatMap (
            node:
            let
              recorded = node.manifest.checks or { };
            in
            builtins.concatMap (
              system:
              builtins.concatMap (
                checkName:
                let
                  check = recorded.${system}.${checkName};
                in
                if check.enable then
                  [
                    {
                      inherit system check checkName;
                      inherit (node) namePath;
                      name = builtins.concatStringsSep "-" (node.parts ++ [ checkName ]);
                    }
                  ]
                else
                  [ ]
              ) (builtins.attrNames recorded.${system})
            ) (builtins.attrNames recorded)
          ) nodes;
          validated =
            entry:
            let
              category = entry.check.category;
            in
            if categories ? ${category} then
              entry // { inherit (categories.${category}) volatile; }
            else
              throw ''
                caisson: the check `${entry.checkName}` of the configuration at ${showNamePath entry.namePath},
                declared at ${showCode entry.check.code}, names the category `${category}`, which no
                configuration declares. Declare it in `caisson.checkCategories.${category}`, or name
                a declared category: ${builtins.concatStringsSep ", " (builtins.attrNames categories)}.
              '';
          publishFor =
            system:
            let
              members = builtins.filter (entry: entry.system == system) entries;
              names = builtins.map (entry: entry.name) members;
              clashing = builtins.filter (
                name: builtins.length (builtins.filter (other: other == name) names) > 1
              ) (unique names);
            in
            if clashing != [ ] then
              throw ''
                caisson: checks.${system}: these checks would be gathered under the same
                name, `${builtins.head clashing}`:
                ${builtins.concatStringsSep "\n" (
                  builtins.map (entry: "  the check `${entry.checkName}` of ${showNamePath entry.namePath}") (
                    builtins.filter (entry: entry.name == builtins.head clashing) members
                  )
                )}
                Rename a check or a configuration.
              ''
            else
              builtins.listToAttrs (
                builtins.map (entry: {
                  inherit (entry) name;
                  value = validated entry;
                }) members
              );
        in
        if staged != [ ] then
          throw ''
            caisson: ${
              builtins.concatStringsSep ", " (builtins.map (node: showNamePath node.namePath) staged)
            } declares stages of checks
            (`caisson.checkStages`), and stages are declared at the caisson top, the
            configuration the checks are gathered at. Declare them there.
          ''
        else
          genAttrs systems publishFor;

      # The checks gathered at the configuration of `manifest`
      # (`gatheredChecksOf`), as derivations by system and then name:
      # `checks` of the outputs of the configuration, which a caisson
      # top publishes.
      checksOf =
        manifest:
        builtins.mapAttrs (_: builtins.mapAttrs (_: entry: entry.check.derivation)) (
          gatheredChecksOf manifest
        );

      # The `checks` output of a caisson top, by system and then name:
      # the gathered checks `caisson.exportedChecks` selected
      # (`gathered`) beside the checks the configurations inside the
      # caisson top publish in
      # `checks` through their `exportsTo` (`published`), as the treefmt
      # integration publishes the check of its configuration named
      # `formatter`. A name in both is refused.
      checksOutputOf =
        { gathered, published }:
        genAttrs (unique (builtins.attrNames gathered ++ builtins.attrNames published)) (
          system:
          let
            fromGathering = gathered.${system} or { };
            fromExports = published.${system} or { };
            both = builtins.attrNames (builtins.intersectAttrs fromGathering fromExports);
          in
          if both != [ ] then
            throw ''
              caisson: checks.${system}: ${
                builtins.concatStringsSep ", " (builtins.map (name: "`${name}`") both)
              } is both a gathered check
              and a check a configuration publishes through its `exportsTo`. Rename the
              check or the configuration.
            ''
          else
            fromGathering // fromExports
        );

      # The system features a check demands of the machine that builds
      # it: the `requiredSystemFeatures` of its derivation, or, for the
      # run of a NixOS test, the features its `config.requiredFeatures`
      # turns on. The test framework builds the run with
      # `lib.lazyDerivation`, whose result carries a fixed set of
      # attributes and the `passthru` of the test, so the run has no
      # `requiredSystemFeatures` attribute. The `passthru` holds the
      # evaluated test as `config`, and its `requiredFeatures` is an
      # attribute set of booleans by feature, from which the framework
      # computes the `requiredSystemFeatures` of the derivation it builds.
      requiredFeaturesOf =
        derivation:
        if derivation ? requiredSystemFeatures then
          derivation.requiredSystemFeatures
        else if builtins.isAttrs (derivation.config or null) && derivation.config ? requiredFeatures then
          builtins.filter (feature: derivation.config.requiredFeatures.${feature}) (
            builtins.attrNames derivation.config.requiredFeatures
          )
        else
          [ ];

      # Whether a gathered check (`gatheredChecksOf`) is of a volatile
      # category. A check of a volatile category runs in a fixed-output
      # derivation (`lib.caisson.mkVolatileCheck`), and one whose
      # derivation has `drvAttrs` that declare no `outputHash` is
      # refused. The tools that act on volatility, such as `topside
      # check`, read it here, in the check record. The `checks` output
      # reads no property of a category, so it does not refuse such a
      # check: reading `volatile` evaluates the declarations of the
      # category, which `nix flake check` has no use for.
      volatileOf =
        entry:
        let
          derivation = entry.check.derivation;
        in
        if !entry.volatile then
          false
        else if builtins.isAttrs (derivation.drvAttrs or null) && derivation.drvAttrs ? outputHash then
          true
        else
          throw ''
            caisson: the check `${entry.checkName}` of the configuration at ${showNamePath entry.namePath},
            declared at ${showCode entry.check.code}, is of the volatile category
            `${entry.check.category}`, and its derivation is not a fixed-output derivation:
            its `drvAttrs` declare no `outputHash`. A check of a volatile category runs in a
            fixed-output derivation, which Nix lets reach the network, and its output is a
            pass marker. Build the derivation with `lib.caisson.mkVolatileCheck`, or name a
            category that is not volatile.
          '';

      # The check record of a caisson top, keyed as `checks` of its
      # outputs is, by system and then published name: for each check,
      # `name` and `system`, `from.namePath`, the path from the caisson
      # top to the
      # configuration that declares the check by the names declared,
      # `category`, `description`, `volatile`, from the category,
      # `requiredFeatures` (`requiredFeaturesOf`), `code`, the
      # positions of the definitions that declare the check, and `top`.
      # For a check of a test caisson top that an entry of
      # `caisson.checks` declares with a `top`, `top` holds the name of
      # that entry as `name`, the name of the check in the test caisson
      # top as `check`, and the entry of the check record of the test
      # caisson top as `record`, null when the test caisson top publishes
      # no check record. For every other check `top` is null.
      #
      # The `volatile` field of a check of a volatile category is
      # refused when the derivation of the check is not a fixed-output
      # derivation (`volatileOf`).
      checkRecordOf =
        manifest:
        builtins.mapAttrs (
          system:
          builtins.mapAttrs (
            name: entry: {
              inherit name system;
              from.namePath = entry.namePath;
              inherit (entry.check)
                category
                description
                code
                top
                ;
              volatile = volatileOf entry;
              requiredFeatures = requiredFeaturesOf entry.check.derivation;
            }
          )
        ) (gatheredChecksOf manifest);

      # The entry of a configuration that is passed up under `prefix`,
      # whose last segment holds the name it is passed up under: the
      # output attribute set and the value its `exportsTo` gives, and
      # its path, on which the name its `exportsTo` gives, where it
      # gives one, stands in place of that name.
      #
      # The entry also carries what the export record of the caisson top holds
      # for it (`recordOf`): `namePath`, its path by the names the
      # configurations are declared under, which is its address under
      # the `children` of the manifests from here; `notes`, the
      # sentence `exportsTo` writes for the name it gives, when it
      # writes a sentence, and then the notes of `level`; and `code`,
      # the positions of what transformed it, those of `level` and then
      # the position of `exportsTo`. `level` is what the configuration
      # that holds this configuration adds for the integration of this
      # configuration: its `exportNote`, as a list, and the files that
      # define its `exported`.
      entryOf =
        level: declared: prefix: manifest: exportsTo:
        let
          leaf = last prefix;
          named =
            if exportsTo ? name then
              exportsTo.name {
                inherit (leaf) name;
                inherit manifest;
              }
            else
              { value = leaf.name; };
        in
        {
          inherit manifest;
          inherit (exportsTo) attrset;
          single = exportsTo.single or false;
          bySystem = exportsTo.bySystem or false;
          system = manifest.system or null;
          value = exportsTo.value manifest;
          path = init prefix ++ [
            (
              leaf
              // {
                name =
                  if hasInfix "/" named.value then
                    throw ''
                      ${exportsTo.attrset}: the configuration at ${showPath prefix} is
                      named `${named.value}`, and a published name may not contain
                      `/`, which separates the parts of a name.
                    ''
                  else
                    named.value;
              }
            )
          ];
          namePath = declared;
          notes = (if named ? description then [ named.description ] else [ ]) ++ level.notes;
          code =
            level.code
            ++ (if (manifest.exportsToPosition or null) == null then [ ] else [ manifest.exportsToPosition ]);
        }
        // (if named ? description then { inherit (named) description; } else { });

      # A published name, from the segments `caisson-core.elide` keeps
      # of a path: the segments in path order, separated by `/`. Every
      # name caisson publishes is written here.
      displayName = builtins.concatStringsSep "/";

      # The entries a configuration passes up for the configurations
      # declared inside it, nested configurations included: for each, its
      # manifest, the output attribute set it is published under, the
      # value published, and its path from here, a list of
      # `{ type, name }` segments. An evaluation result of a configuration
      # evaluated per system has its system above its name on the
      # path. `selected`
      # is what each integration's `exported` selected, by integration
      # and then name, each value a manifest or the evaluation results of a
      # configuration by system. A configuration whose manifest
      # records `exportsTo` is an entry, made here, where the name it
      # is passed up under is known, from what the manifest records;
      # and every configuration contributes the entries it passes up
      # in turn, with its segments in front. An entry carries all a
      # caisson top needs to publish it.
      #
      # `levels` is what this configuration adds, by integration, to
      # the entries of the configurations of that integration it passes
      # up, nested configurations included: `notes`, its `exportNote` as a list,
      # and `code`, the positions of the definitions of its `exported`.
      # The segments of `namePath` carry the names the configurations
      # are declared under, which a parent's `exported` may have
      # changed on `path`.
      entriesOf =
        levels: selected:
        builtins.concatMap (
          integration:
          builtins.concatMap (
            name:
            let
              finalized = selected.${integration}.${name};
              level =
                levels.${integration} or {
                  notes = [ ];
                  code = [ ];
                };
              segmentOf = name: {
                type = integration;
                inherit name;
              };
              systemSegment = system: {
                type = "system";
                name = system;
              };
              evaluations =
                if isManifest finalized || final.caisson-core.isDeferred finalized then
                  [
                    {
                      prefix = [ (segmentOf name) ];
                      declared = [ (segmentOf finalized.name) ];
                      manifest = finalized;
                    }
                  ]
                else
                  builtins.map (system: {
                    prefix = [
                      (systemSegment system)
                      (segmentOf name)
                    ];
                    declared = [
                      (systemSegment system)
                      (segmentOf finalized.${system}.name)
                    ];
                    manifest = finalized.${system};
                  }) (builtins.attrNames finalized);
            in
            builtins.concatMap (
              {
                prefix,
                declared,
                manifest,
              }:
              builtins.map (entryOf level declared prefix manifest) (exportsOf manifest)
              # The entry of a deferred child is published as its
              # `exportsTo` says, and no configuration declared inside it is
              # evaluated at flake time, so it passes nothing else up.
              ++ (
                if final.caisson-core.isDeferred manifest then
                  [ ]
                else
                  builtins.map (
                    entry:
                    entry
                    // {
                      path = prefix ++ entry.path;
                      namePath = declared ++ entry.namePath;
                      notes = entry.notes ++ level.notes;
                      code = entry.code ++ level.code;
                    }
                  ) (manifest.outputs.exports.configurations or [ ])
              )
            ) evaluations
          ) (builtins.attrNames selected.${integration})
        ) (builtins.attrNames selected);

      # What a caisson top publishes of the entries passed up to it, by
      # the output attribute set each entry carries and then name. The
      # caisson top reads nothing but the entries. Within an attribute set the names come from
      # `caisson-core.elide` over the paths: a name that is alone stays
      # bare, and names that collide gain the segments that tell them
      # apart. Entries that still share a name are refused, with their
      # paths.
      #
      # An output that holds a single value (`colmenaHive`) is the value
      # of the entry named for that output, `colmenaHive`, the entry
      # whose `exportsTo` says `single`. Any other entry for that output is refused, since the
      # output has no names to hold it under.
      #
      # An output whose entries' `exportsTo` says `bySystem` is keyed by
      # the system of each evaluation result first, as flakes key `packages`
      # and `formatter`: `<attrset>.<system>`, holding the entries
      # evaluated for that system, named by the rules above over their
      # paths without the systems on them, or the single value there.
      publish = entries: publicationOf (entry: entry.value) entries;

      # The export record of a caisson top, keyed as `publish` keys the
      # outputs: for each name published, `from.namePath`, the path from
      # the caisson top to the manifest of the configuration by the
      # names declared, which is its address under the `children` of the
      # manifest of the caisson top; `notes`, the sentences each side that transformed the
      # configuration on the way up wrote, from the configuration up to
      # the caisson top; and `code`, the positions of that code, the
      # definitions of each `exported` and each integration's
      # `exportsTo`, in the same order.
      recordOf =
        entries:
        publicationOf (entry: {
          from.namePath = entry.namePath;
          inherit (entry) notes code;
        }) entries;

      # What `publish` and `recordOf` key by name, `of` of each entry.
      publicationOf =
        of: entries:
        let
          attrsets = unique (builtins.map (entry: entry.attrset) entries);
          publishIn =
            attrset:
            let
              members = builtins.filter (entry: entry.attrset == attrset) entries;
              keyed = builtins.filter (entry: entry.bySystem or false) members;
              systems = unique (builtins.map (entry: entry.system) keyed);
              withoutSystems =
                entry: entry // { path = builtins.filter (segment: segment.type != "system") entry.path; };
            in
            if keyed == [ ] then
              publishMembers attrset members
            else if builtins.length keyed != builtins.length members || builtins.elem null systems then
              throw ''
                ${attrset}: this output is keyed by system, and these configurations
                would be published there without a system:
                ${builtins.concatStringsSep "\n" (
                  builtins.map (entry: "  ${showPath entry.path}") (
                    builtins.filter (entry: !(entry.bySystem or false) || entry.system == null) members
                  )
                )}
              ''
            else
              genAttrs systems (
                system:
                publishMembers "${attrset}.${system}" (
                  builtins.map withoutSystems (builtins.filter (entry: entry.system == system) keyed)
                )
              );
          publishMembers =
            attrset: members:
            let
              names = builtins.map displayName (
                final.caisson-core.elide (builtins.map (entry: entry.path) members)
              );
              named = zipListsWith (name: entry: { inherit name entry; }) names members;
              clashing = builtins.filter (
                name: builtins.length (builtins.filter (other: other == name) names) > 1
              ) (unique names);
              single = builtins.any (entry: entry.single or false) members;
              # A configuration with a single output is named for that
              # output.
              misnamed = builtins.filter (entry: (last entry.path).name != entry.attrset) members;
              singleName = (builtins.head members).attrset;
            in
            if single then
              if builtins.length members == 1 && misnamed == [ ] then
                of (builtins.head members)
              else
                throw ''
                  ${attrset}: this output holds a single value, the configuration
                  declared under the name `${singleName}`, but these configurations would
                  be published there:
                  ${builtins.concatStringsSep "\n" (builtins.map (entry: "  ${showPath entry.path}") members)}
                ''
            else if clashing != [ ] then
              throw ''
                ${attrset}: these configurations would be published under the same
                name, `${builtins.head clashing}`:
                ${builtins.concatStringsSep "\n" (
                  builtins.map (item: "  ${showPath item.entry.path}") (
                    builtins.filter (item: item.name == builtins.head clashing) named
                  )
                )}
              ''
            else
              builtins.listToAttrs (
                builtins.map (item: {
                  inherit (item) name;
                  value = of item.entry;
                }) named
              );
        in
        genAttrs attrsets publishIn;

      # What a tool reads from a caisson top that is a configuration
      # evaluated per system, given its evaluation results by system. They
      # are named like anything published, by `caisson-core.elide` over
      # their paths; the caisson top is addressed by the file that returns
      # it, so the name of the caisson top is left out of each. Where that leaves a single
      # evaluation result with no name, the result is its value, the evaluated
      # configuration; otherwise it is the values by what is left of
      # each name.
      topValue =
        evaluations:
        let
          systems = builtins.attrNames evaluations;
          kept = final.caisson-core.elide (
            builtins.map (system: [
              {
                type = "system";
                name = system;
              }
              {
                inherit (evaluations.${system}) type;
                name = evaluations.${system}.name or "";
              }
            ]) systems
          );
          names = builtins.map (segments: displayName (init segments)) kept;
        in
        if names == [ "" ] then
          evaluations.${builtins.head systems}.value
        else
          builtins.listToAttrs (
            zipListsWith (name: system: {
              inherit name;
              inherit (evaluations.${system}) value;
            }) names systems
          );

      # An integration that evaluates a class another integration
      # owns, declared: `over` is the owning integration, reached
      # through the lib (`final.caisson.nixos`), and the class and its
      # registration form belong to that integration; the entry points
      # build on the composition that integration publishes, so the
      # evaluators cannot express different configurations from the
      # same arguments. The result is the value of `lib.caisson.<name>`:
      # the entry points, the `types` of the owner and `extra`, no
      # `mkModule`, and no class declaration.
      mkAltIntegration =
        {
          over,
          mkConfiguration,
          mkConfigurationWithEcosystemArgs,
          # As for `mkIntegration`.
          top ? null,
          extra ? { },
        }:
        assert builtins.isAttrs over && over ? mkModule;
        {
          inherit mkConfiguration mkConfigurationWithEcosystemArgs;
          # Its modules are of the class of the owner, and its
          # configurations are configurations of the owner.
          inherit (over) types;
        }
        // (if top == null then { } else { mkTopConfiguration = topConfiguration top mkConfiguration; })
        // extra;

    in
    {
      # The option types the core module of caisson declares its
      # options with (modules/generic/caisson/types.nix), built on the
      # library of nixpkgs in this library. caisson-core is written on
      # builtins alone, and an option type is built on the library of
      # nixpkgs, so caisson adds the types to the namespace of
      # caisson-core here, beside the manifests they type.
      caisson-core = (prev.caisson-core or { }) // {
        types = import ../../modules/generic/caisson/types.nix { lib = final; };
      };

      caisson = (prev.caisson or { }) // {
        integrations = ((prev.caisson or { }).integrations or { }) // {
          inherit
            checkDeclarationsOf
            checkRecordOf
            checksOf
            checksOutputOf
            childrenOf
            definitionCodeOf
            showCode
            displayName
            declarationEventsOf
            ecosystemUnit
            inEcosystem
            entriesOf
            positionOf
            configurationsModuleFor
            integrationsIn
            integrationsDeclaringIn
            nearestOf
            belongsHere
            recordOf
            activatingAncestorOf
            machineProfilesOf
            machineActivation
            markerFileName
            markerOf
            checksMarkerOf
            driftCheckOf
            safeName
            profileOf
            profileShimsOf
            profilesActivatedBy
            profileChoicesOf
            mkEvaluation
            publish
            topValue
            resolveEcosystemSrc
            selectedEcosystemSrc
            ecosystemAccountOf
            pkgSetAccountOf
            namespacesOf
            mkIntegration
            mkAltIntegration
            typesOf
            frameworkModules
            configModuleOf
            caissonModule
            mkModuleConfiguration
            moduleImportsOf
            pkgSetOf
            pkgSetsForSystem
            ;
          coreModules = select "core";
          defaultModuleImports = select "default";
        };
      };
    };

}
