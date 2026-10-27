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
#                        few of its target) and composes the evaluator's
#                        call from them. Nothing else is forwarded: an
#                        evaluator argument handed in directly would be
#                        silently overwritten, silently dropped, or
#                        surface as a conflict deep inside the
#                        evaluator. The `...WithEcosystemArgs` twin of
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
#                        sources are read from the composition's
#                        manifest; a manifest-less
#                        composition resolves only the explicit
#                        argument.
#   coreModules          the selections every integration draws
#   defaultModuleImports from the registry of its class, by entry name:
#                        every entry named `core` (the local `core` and
#                        a consumed project's `<project>/core`) is the
#                        framework module of the class, forced into
#                        every evaluation before anything the
#                        evaluation selects; every entry named
#                        `default`, likewise, is the default default,
#                        what `moduleImports` selects when the
#                        evaluation names nothing. Any project a
#                        composition lists may register either, for any
#                        class: a `core` is the big hammer, for a module
#                        the class cannot function without; a `default`
#                        is what the project gives every configuration
#                        of the class unless it selects otherwise.
#   frameworkModules     the framework module of a class, forced into
#                        every evaluation of it: the core of caisson
#                        itself for the class, which declares the
#                        manifest, the configurations declared beneath
#                        and `caisson.exports`, followed by
#                        `coreModules` of the registry.
#   mkModuleConfiguration
#                        a configuration that is a module evaluation,
#                        from the evaluator step of an integration.
#                        It holds configurations of any integration
#                        beneath it: the configurations its modules
#                        declare are its children, and what they
#                        export is passed up through it.
{ closure-lib, mkLibOverlay, ... }:
{

  # These functions use `builtins` and the list, attribute set, string
  # and function helpers of caisson-core (`caisson-core.lists` and its
  # neighbours), so this overlay composes in a library that holds no
  # library of nixpkgs. An integration that evaluates modules imports
  # that library itself. The one import is the names of the framework
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
      # argument is a function of the tree's pinned sources, as
      # `defaultEcosystemSrc` on mkLib is, so a configuration chooses
      # among the sources the tree pins. Null when the configuration
      # passes none. `manifest` is the manifest whose `sources` it
      # selects from, the lib manifest of the evaluation.
      selectedEcosystemSrc =
        context: manifest: explicit:
        if explicit == null then
          null
        else if builtins.isFunction explicit then
          explicit (manifest.sources or { })
        else
          throw ''
            ${context}: `ecosystemSrc` is a function of the tree's sources that
            returns the source to use, `ecosystemSrc = sources: sources.<name>;`,
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
            sources = manifest.sources or { };
          };
        in
        if resolved != null then
          resolved
        else
          throw ''
            ${context}: no ${name} ecosystem source. Select one with
            `ecosystemSrc = sources: sources.<name>;` on the configuration,
            return a `${name}` from the `defaultEcosystemSrc` function of the
            mkLib call, or pin a source named `${name}` in the `sources` passed
            to mkLib.
          '';

      # How an evaluation came by the source of the ecosystem `name`, as
      # its manifest records it under `ecosystems.<name>`. It takes the
      # arguments `resolveEcosystemSrc` takes and follows the same
      # order. `from` names the declaration that supplied the source:
      # `ecosystemSrc` for the selection of the configuration,
      # `defaultEcosystemSrc` for the selection of the tree, and
      # `sources` for the source the tree pins under exactly that name.
      # `source` is the name of that source among the pinned sources,
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
          sources = manifest.sources or { };
        in
        if explicit != null then
          {
            from = "ecosystemSrc";
            source = final.caisson-core.selectedSourceName {
              inherit sources;
              selection = sources: selectedEcosystemSrc context { inherit sources; } explicit;
            };
          }
        else if (manifest.defaultEcosystemSrc or { }) ? ${name} then
          {
            from = "defaultEcosystemSrc";
            source = (manifest.defaultEcosystemSrcNames or { }).${name} or null;
          }
        else if sources ? ${name} then
          {
            from = "sources";
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

      # A module an integration adds to an evaluation itself, keyed
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

      # The `declaration` events of an evaluation: an event for each
      # element of `modules`, the list the integration hands the
      # evaluator, in that order, with the module list of the ecosystem
      # as the single event of its `ecosystemUnit`. A module selected
      # from the registry carries its registry key in its module key
      # (`lib.caisson.modules`): the event is keyed by the registry key,
      # with the name the registry it was read from gives the entry, and
      # its origin is the project that registered the module and the
      # file of the module, where the module has a file. An entry of a
      # listed project read from the registry of the tree is therefore
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
      # lib of the evaluation.
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

      # How an evaluation of the class `class`, constructed with `args`,
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
      # - `default`: the default in force, whatever the act, as
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

      # The selection of an evaluation over the registry of its class,
      # from the arguments of the configuration, as a function of that
      # registry: what `moduleImports` selects, and with none
      # given the default of the class, every entry named `default`
      # followed by what the levels above the evaluation added for the
      # class (`caisson.forChildren.extraDefaultModuleImports`), then
      # what they added for the nearest configurations of the class
      # where this evaluation is one of them
      # (`caisson.forNearestChildren.extraDefaultModuleImports`), each
      # applied to the lib of the evaluation.
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

      # The package sets available to an evaluation, by package config
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

      # The package set a configuration runs on: the selection in
      # force at its manifest, applied to the package sets available
      # to it. A selection is a function that receives those sets, as
      # an attribute set by package config name, and returns the set to
      # run on. The `defaultPkgs` argument of a constructor makes one for
      # that configuration and everything beneath it
      # (`mkModuleConfiguration` records it), and a configuration that
      # passes none runs on what the nearest configuration above it
      # selected. Where no configuration from the top down to this one
      # selected, it runs on the set named `default`. Every integration
      # whose configurations run on a package set selects it here.
      pkgSetOf =
        { context, what }:
        manifest: pkgSets:
        if (manifest.defaultPkgs or null) != null then
          manifest.defaultPkgs pkgSets
        else
          pkgSets.default or (throw ''
            ${context}: ${what} runs on the package set named `default`,
            since no configuration from the top down to it selects one, and the
            package sets available here are ${
              if pkgSets == { } then "none" else builtins.concatStringsSep ", " (builtins.attrNames pkgSets)
            }. Declare a package config named `default` with `pkgSets` on mkLib,
            or select a set where a configuration is constructed
            (`defaultPkgs = pkgSets: pkgSets.<name>;`).
          '');

      # Which package config a configuration runs on, as its manifest
      # records it under `pkgSet`. `name` is the name of the package
      # config whose set the selection in force at `manifest` returns.
      # It is read from the selection applied to `pkgSets` tagged with
      # their names, so it is null where the selection returns a set it
      # builds in another way. `level` is the name path of the
      # configuration that made the selection: the configuration itself
      # when `own` says it was constructed with `defaultPkgs`, else the
      # nearest configuration above that selected for the
      # configurations beneath it. Where no configuration selects,
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
      # the package set selection in force at `manifest`: the nearest
      # parent that selects for the configurations beneath it with
      # `caisson.forChildren.defaultPkgs`, or else the level a parent
      # records for its own selection. A system between a configuration
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

      # The names of the namespaces of the lib an evaluation runs on, as
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

      # A configuration that is a module evaluation. `type` is the
      # name of the integration and `perSystem` whether it evaluates a
      # configuration per system, as caisson-core.mkConfiguration
      # takes them. `evaluate` is the evaluator step of the
      # integration: it takes the view being evaluated, `{ lib,
      # manifest }`, and returns `value`, the evaluation as the
      # evaluator returned it, `outputs`, the references into it that
      # the integration declares, and `config` where the evaluated
      # options are not `value.config`. Its module list carries
      # `frameworkModules` of its class.
      #
      # The configurations its modules declare under
      # `caisson.<integration>.configurations`, of any integration,
      # are its children, and `caisson.exports`, which carries what
      # they pass up, is its `exports` output. An integration whose
      # evaluation finalizes its children itself returns them as
      # `children`, by integration and then name, and they are its
      # children in place of those values. A deferred configuration
      # (`caisson-core.mkDeferredConfiguration`) finalizes the deferred
      # configurations declared beneath it this way, with their part of
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
      # recorded on the manifest, where it is in force for the
      # configuration and everything beneath it.
      #
      # `exportsTo` says how the configuration is published: `attrset`,
      # the output attribute set (`nixosConfigurations`), and `value`,
      # the function from the manifest of the configuration to what is
      # published. It may carry `name`, for an integration whose
      # configurations are known by a name other than the one they are
      # declared under: a function of `{ name, manifest }`, the name
      # the configuration is passed up under and its manifest,
      # returning `value`, the name to publish it under, and
      # optionally `description`, a sentence saying what it did. It may
      # carry `single`, for an output that holds the one configuration
      # named for that output, and `bySystem`, for an output keyed by the
      # system of each evaluation first (`packages.<system>.<name>`). It
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
      # are activated on a machine or for a user: NixOS, darwin and
      # system-manager machines, home-manager configurations, hjem
      # configurations. It holds
      # two functions of a manifest of the configuration. `identity`
      # returns the store path that names what the activation applies,
      # computed from the childless evaluation, or null where there is
      # none. `standsAlone`, when true, says the configuration is
      # applied on its own, as a machine is on its own host, so that it
      # checks no configuration above it. `marker` returns the path of the file the activation
      # writes that identity into, as shell text, which may name
      # variables such as `$HOME`. It is recorded on the manifest. A
      # configuration with an activation declared beneath one checks
      # the marker of the nearest such configuration above it when it
      # is activated (`driftCheckOf`). Null for a configuration that is
      # not activated.
      #
      # `selection` is `{ class; args; }`, the class of the evaluation
      # and the arguments the configuration was constructed with, from
      # which the manifest records how the evaluation selected its
      # modules as `moduleImports` (`selectionAccountOf`). Null for a
      # configuration whose modules are not selected from a class.
      #
      # What the modules give the configurations beneath is read from
      # `caisson.forChildren` and `caisson.forNearestChildren`
      # (`additionsOf`).
      mkModuleConfiguration =
        args@{
          type,
          perSystem ? false,
          defaultPkgs ? null,
          exportsTo ? null,
          activation ? null,
          selection ? null,
          evaluate,
        }:
        final.caisson-core.mkConfiguration {
          inherit type perSystem;
          # The class of the evaluation, where the additions for the
          # nearest children of that class connect.
          class = if selection == null then null else selection.class;
          recordFromEvaluation = [
            "ecosystems"
            "namespaces"
            "pkgSet"
          ]
          ++ (if selection == null then [ ] else [ "moduleImports" ]);
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
            // (if activation == null then { } else { inherit activation; });
          evaluate =
            view:
            let
              evaluated = evaluate view;
              config = evaluated.config or evaluated.value.config;
              options = evaluated.options or evaluated.value.options;
            in
            {
              inherit (evaluated) value;
              outputs = (evaluated.outputs or { }) // {
                exports = config.caisson.exports;
              };
              children =
                evaluated.children or (view.lib.caisson.integrations.childrenOf { inherit options config; });
              # What the modules give the configurations beneath
              # (`caisson.forChildren`).
              forChildren = {
                extraDefaultModuleImports = additionsOf options.caisson.forChildren config.caisson.forChildren;
                defaultPkgs = config.caisson.forChildren.defaultPkgs;
                systems = config.caisson.forChildren.systems;
                inherit (config.caisson.forChildren) unsafeCrossChildReferences;
              };
              # What the modules give the nearest configurations of a
              # class beneath (`caisson.forNearestChildren`).
              forNearestChildren = {
                extraDefaultModuleImports = additionsOf options.caisson.forNearestChildren config.caisson.forNearestChildren;
                inherit (config.caisson.forNearestChildren) unsafeCrossChildReferences;
              };
              # What the modules give the configurations of a class
              # declared directly beneath (`caisson.forDirectChildren`).
              forDirectChildren = {
                extraDefaultModuleImports = additionsOf options.caisson.forDirectChildren config.caisson.forDirectChildren;
                inherit (config.caisson.forDirectChildren) unsafeCrossChildReferences;
              };
              # What the evaluator received, as `declaration` events:
              # the integration's `evaluate` returns `modules`, the list
              # it handed the evaluator, with an `ecosystemUnit` where
              # the module list of the ecosystem is.
              events = declarationEventsOf {
                inherit (view) lib;
                modules = evaluated.modules or [ ];
              };
              record = {
                # Where each part of the stack the evaluation used came
                # from (`ecosystemAccountOf`): the library of the lib it
                # runs on, and each ecosystem the integration resolved,
                # which its `evaluate` returns as `ecosystems`.
                ecosystems = {
                  nixpkgs-lib = ecosystemAccountOf {
                    name = "nixpkgs-lib";
                    context = "the nixpkgs-lib entry";
                  } { manifest = view.lib.caisson-core.libManifest or { }; };
                }
                // (evaluated.ecosystems or { });
                # The names of the namespaces of the lib the evaluation
                # runs on (`namespacesOf`).
                namespaces = namespacesOf view.lib;
              }
              # Which package config the evaluation runs on and the
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
                    view.manifest
                    (
                      pkgSetsForSystem {
                        context = "the pkgSet record";
                        what = "the configuration";
                      } view.manifest view.manifest.system
                    );
              }
              # How the evaluation selected its modules.
              // (if selection == null then { } else { moduleImports = selectionAccountOf selection view; });
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
      # and the call to make. `ecosystemArgs`, which only the twin's
      # pattern admits, is merged over the composed call verbatim,
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

      # An integration that owns a module class, declared. The
      # declaration carries the entry points as pattern functions,
      # `mkConfiguration` and its `WithEcosystemArgs` twin, and the
      # result holds `namespace`, the value of `lib.caisson.<name>`: the
      # entry points, the registration form `mkModule` bound to the
      # class, `configurationsModule`, and whatever `extra` adds beside
      # them (variants, and the composition an alt over the class
      # reads). The overlay file writes the namespace under its key,
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
          # arguments apply to all of them; a tree that wants only some,
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
            configurationsModule = configurationsModuleOf name;
          }
          // (if findsModuleByName then { inherit mkConfigurations; } else { })
          // (if top == null then { } else { inherit mkTopConfiguration; })
          // extra;
        };

      # The module of the integration `name` that lets a configuration
      # hold configurations of that integration beneath it. It declares
      # `caisson.<name>.configurations`, which takes what
      # `lib.caisson.<name>.mkConfiguration` returns and holds the
      # finished manifest, and `caisson.<name>.exported`, which selects
      # those that are passed up. A configuration learns its name and
      # its parent from where it is declared, so the option finalizes
      # each entry when it is read, with the attribute it is declared
      # under and the childless manifest of the evaluation. caisson's
      # core module imports this module for each integration of
      # caisson. An integration written outside caisson registers a
      # module that imports it where its configurations may be declared.
      configurationsModuleOf = name: configurationsModuleFor [ name ];

      # The module that declares the options `configurationsModuleOf`
      # declares, for several integrations at once. The core module of
      # caisson imports it once, for all the integrations of caisson.
      # The types of the options are built once for all of them.
      configurationsModuleFor = names: {
        key = "caisson-configurations:${builtins.concatStringsSep "," names}";
        imports = [
          (
            { lib, options, ... }:
            let
              types = configurationsTypesOf lib;
            in
            {
              options.caisson = genAttrs names (
                name: configurationsOptionsOf { inherit lib options types; } name
              );
            }
          )
        ];
      };

      # The types of `caisson.<name>.configurations` and
      # `caisson.<name>.exported`, the same for every integration.
      configurationsTypesOf = lib: {
        configurations = lib.types.lazyAttrsOf lib.types.raw;
        exported = lib.types.functionTo (lib.types.lazyAttrsOf lib.types.raw);
      };

      # The options `caisson.<name>.configurations` and
      # `caisson.<name>.exported` of the integration `name`, in the
      # evaluation whose `lib` and `options` are given, with `types` from
      # `configurationsTypesOf`.
      configurationsOptionsOf =
        {
          lib,
          options,
          types ? configurationsTypesOf lib,
        }:
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
              # The integration of what was declared: of the
              # manifest, or of the evaluations of a configuration
              # evaluated per system, null where it has none.
              declaredType =
                if isManifest finalized || lib.caisson-core.isDeferred finalized then
                  finalized.type
                else if finalized == { } then
                  null
                else
                  (builtins.head (builtins.attrValues finalized)).type;
            in
            if manifest == null then
              throw ''
                ${what childName} is declared in an evaluation that carries no manifest
                (`lib.caisson-core.evalManifest` is null there), so no
                configuration can be finalized beneath it.
              ''
            else if manifest.childless then
              throw ''
                The result of the ${name} configuration `${childName}` is not
                readable from the ${manifest.type} configuration it is declared in, or
                from another configuration beneath that configuration; only the
                options of the ${manifest.type} configuration are readable there.
                Put the value in one of those options and read it there.
              ''
            else if declaredType != null && declaredType != name then
              throw (
                if builtins.elem declaredType (integrationsIn options) then
                  ''
                    ${what childName} is declared with a ${declaredType} configuration.
                    Declare it under `caisson.${declaredType}.configurations`.
                  ''
                else
                  ''
                    ${what childName} is declared with a ${declaredType} configuration, and a
                    ${declaredType} configuration cannot be declared beneath another
                    configuration.
                  ''
              )
            else
              finalized;
        in
        {
          exported = lib.mkOption {
            type = types.exported;
            default = configurations: configurations;
            defaultText = lib.literalMD "every configuration declared";
            description = ''
              Function that selects which of the ${name} configurations
              declared beneath this configuration it passes up. Receives
              `caisson.${name}.configurations` and returns the subset to
              export; `_: { }` exports none. What each selected configuration
              exports is merged into this configuration's `caisson.exports`.
            '';
          };
          exportNote = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "office machines carry the site prefix; lab machines are never deployed from this flake";
            description = ''
              A sentence saying what `caisson.${name}.exported` does to the
              ${name} configurations it passes up, for a selector that does
              more than pass every configuration up unchanged. The top
              records it in the export record (`exportRecord` of the
              manifest it publishes) for each name published from those
              configurations, with the notes of the levels beneath.
            '';
          };
          configurations = lib.mkOption {
            type = types.configurations;
            default = { };
            apply = builtins.mapAttrs finalize;
            description = ''
              The ${name} configurations declared beneath this
              configuration, by name: each is what
              `lib.caisson.${name}.mkConfiguration` returns, and reads
              back as its manifest, finalized with the name it is declared
              under and this configuration as its parent. A configuration
              beneath sees this configuration without the configurations declared
              beneath it, so a definition that reads one of them is guarded
              with `!lib.caisson-core.evalManifest.childless`.
            '';
          };
        };

      # The integrations whose configurations an evaluation can hold
      # beneath it: those whose `configurationsModule` the evaluation
      # imports, read from its options. The module declares both
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
      # `caisson.<integration>.configurations` a module of the evaluation
      # defines: those whose highest priority is above the priority of
      # an option default. The others hold no configurations, so neither
      # their configurations nor their `exported` selector is read, which
      # spares merging those options in every evaluation for every
      # integration the evaluation could hold.
      integrationsDeclaringIn =
        options:
        builtins.filter (name: options.caisson.${name}.configurations.highestPrio < 1500) (
          integrationsIn options
        );

      # The configurations an evaluated configuration declares beneath
      # it, by integration and then name, as the `children` an
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
      # configuration. The path of the entry runs from beneath that
      # configuration down to the entry, so the entry belongs to it
      # when no segment of the path before the last is of `type`.
      # Segments of other integrations and systems do not count. A
      # colmena configuration builds its nodes from the NixOS
      # configurations that belong to it in this sense:
      # `belongsHere "nixos"` keeps a machine beneath a disk layout or a
      # structural group and leaves out a NixOS configuration declared
      # inside a node.
      belongsHere = type: entry: !(builtins.any (segment: segment.type == type) (init entry.path));

      # The nearest configuration above `manifest` whose integration is
      # one of `types`, null when there is none. The manifest records
      # the nearest ancestor of each integration; of those, the nearest
      # is the ancestor with the most ancestors itself. A home-manager
      # configuration reads its machine this way, which is a NixOS or a
      # darwin configuration.
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
      # configuration inside a NixOS machine finds the machine; an nvf
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

      # The `activation` of a machine: a NixOS, darwin or system-manager
      # configuration. Its identity is its system, `toplevel`, null for
      # a configuration that builds none, as the nixos-minimal
      # integration can produce. Its marker is a file under `/etc`,
      # which the module `activation-marker` of its class writes.
      #
      # A machine is activated on its own host. A machine declared
      # inside another, such as an image, is applied on a different host
      # than the machine above, and the marker under `/etc` that it
      # finds there is its own, so it checks nothing above it:
      # `standsAlone`.
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
      # store path. Computing the store path evaluates the childless
      # evaluation and builds nothing, and the digest refers to no store
      # path, so a marker that holds it depends on nothing. The digest
      # is compared, never read as a path.
      digestOf = identity: builtins.hashString "sha256" identity;

      # What the activation of the configuration of `manifest` writes
      # into its marker: the digest of the identity of its childless
      # evaluation (`digestOf`). `path` is the shell text of the path of
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

      # Where a configuration is in the tree: the integration and the name
      # of each configuration from the top down to it, the nodes of the
      # systems included. Configurations at the same depth have
      # different places, such as a home-manager configuration and a
      # hjem configuration inside the same machine, and the childless
      # and the full manifest of a
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
      # activation. When that configuration activates this one, its
      # marker already belongs to the generation being activated, and
      # the check prints nothing. Empty when there is no such
      # configuration, or it has no identity. `jq` is the path of a jq
      # executable, and `optionText` names the option that turns the
      # warning off, for the message.
      driftCheckOf =
        { jq, optionText }:
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
              fi
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
      # Neovim, kept in a Nix profile of its own, the way a home-manager
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
      # a machine it is a profile of the system,
      # `/nix/var/nix/profiles/caisson/<kind>/<name>`, which the machine
      # activates as root. Inside a home-manager configuration or a hjem
      # configuration, or as a top, it is a profile of the user,
      # `$HOME/.local/state/caisson/profiles/<kind>/<name>`. The path
      # names `$HOME` and not `$XDG_STATE_HOME`: the units of a machine
      # run without `$XDG_STATE_HOME`, and a shell may set it, and the
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
      # activation is this one. A profile inside a home-manager
      # configuration inside this machine is activated by that
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
      # programs of all of them. The profile is the one `selected` names
      # for the variable, as `<kind>/<name>`, or the only one. `what`
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
                  throw "caisson: ${what} activates several profiles chosen with `${variable}` (${builtins.concatStringsSep ", " (builtins.map nameOf sharing)}). Set `caisson.profiles.selected.${variable}` to the one a shell runs when it sets no other.";
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

      # A position as the export record holds it: the file and the line
      # number (`line`) of what `builtins.unsafeGetAttrPos` returns, null
      # when it returns none.
      positionOf = position: if position == null then null else { inherit (position) file line; };

      # The entry of a configuration that is passed up under `prefix`,
      # whose last segment holds the name it is passed up under: the
      # output attribute set and the value its `exportsTo` gives, and
      # its path, on which the name its `exportsTo` gives, where it
      # gives one, stands in place of that name.
      #
      # The entry also carries what the export record of the top holds
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
      # declared beneath it, nested ones included: for each, its
      # manifest, the output attribute set it is published under, the
      # value published, and its path from here, a list of
      # `{ type, name }` segments. An evaluation of a configuration
      # evaluated per system has its system above its name on the
      # path. `selected`
      # is what each integration's `exported` selected, by integration
      # and then name, each value a manifest or the evaluations of a
      # configuration by system. A configuration whose manifest
      # records `exportsTo` is an entry, made here, where the name it
      # is passed up under is known, from what the manifest records;
      # and every configuration contributes the entries it passes up
      # in turn, with its segments in front. An entry carries all a
      # top needs to publish it.
      #
      # `levels` is what this configuration adds, by integration, to
      # the entries of the configurations of that integration it passes
      # up, nested ones included: `notes`, its `exportNote` as a list,
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
              beneath =
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
              # `exportsTo` says, and nothing beneath it is evaluated at
              # flake time, so it passes nothing else up.
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
            ) beneath
          ) (builtins.attrNames selected.${integration})
        ) (builtins.attrNames selected);

      # What a top publishes of the entries passed up to it, by the
      # output attribute set each entry carries and then name. The
      # top reads nothing but the entries. Within an attribute set the names come from
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
      # the system of each evaluation first, as flakes key `packages`
      # and `formatter`: `<attrset>.<system>`, holding the entries
      # evaluated for that system, named by the rules above over their
      # paths without the systems on them, or the single value there.
      publish = entries: publicationOf (entry: entry.value) entries;

      # The export record of a top, keyed as `publish` keys the outputs:
      # for each name published, `from.namePath`, the path from the top
      # to the manifest of the configuration by the names declared,
      # which is its address under the `children` of the top's
      # manifest; `notes`, the sentences each side that transformed the
      # configuration on the way up wrote, from the configuration up to
      # the top; and `code`, the positions of that code, the
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

      # What a tool reads from a top that is a configuration evaluated
      # per system, given its evaluations by system. They are named
      # like anything published, by `caisson-core.elide` over their
      # paths; the top is addressed by the file that returns it, so the
      # name of the top is left out of each. Where that leaves a single
      # evaluation with no name, the result is its value, the evaluated
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
      # the entry points and `extra`, no `mkModule`, and no class
      # declaration.
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
        }
        // (if top == null then { } else { mkTopConfiguration = topConfiguration top mkConfiguration; })
        // extra;

    in
    {
      caisson = (prev.caisson or { }) // {
        integrations = ((prev.caisson or { }).integrations or { }) // {
          inherit
            childrenOf
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
