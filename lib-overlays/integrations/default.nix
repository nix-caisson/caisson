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
{ closure-lib, ... }:
{

  # Nothing is imported: these functions use `builtins` and the list,
  # attribute set, string and function helpers of caisson-core
  # (`caisson-core.lists` and its neighbours), so this overlay
  # composes in a library that holds no library of nixpkgs. An
  # integration that evaluates modules imports that library itself.
  imports = [ ];

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
            inherit name explicit;
            defaults = manifest.defaultEcosystemSrc or { };
            sources = manifest.sources or { };
          };
        in
        if resolved != null then
          resolved
        else
          throw ''
            ${context}: no ${name} ecosystem source. Pass `ecosystemSrc`
            explicitly, declare `defaultEcosystemSrc.${name}` in the mkLib call,
            or pin a source named `${name}` in the `sources` passed to mkLib.
          '';

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
        class: registry: [ closure-lib.caisson-core.modules.${class}.core ] ++ select "core" registry;

      # The selection of an evaluation over the registry of its class,
      # from the arguments of the configuration, as a function of that
      # registry: what `moduleImports` selects, and with none
      # given the default of the class, every entry named `default`
      # followed by what the levels above the evaluation added for the
      # class (`caisson.forChildren.defaultModuleImports`), each
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
            ++ builtins.concatMap (selection: selection lib) (manifest.defaultModuleImports.${class} or [ ])
        )
        ++ (if extra == null then [ ] else extra registry);

      # The package sets available to an evaluation, by package config
      # name: the package configs its manifest holds, each projected to
      # its set at `system`. `context` names the entry point and `what`
      # the configuration, for the message of a config that builds no
      # set at that system.
      pkgSetsAt =
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

      # A configuration that is a module evaluation. `type` is the
      # name of the integration and `perSystem` whether it evaluates a
      # configuration at a system, as caisson-core.mkConfiguration
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
      # they pass up, is its `exports` output.
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
      # optionally `description`, a sentence saying what it did. It is
      # recorded on the manifest, and applied where the configuration
      # is passed up (`entriesOf`). Null for a configuration that is
      # not published under a name.
      mkModuleConfiguration =
        {
          type,
          perSystem ? false,
          defaultPkgs ? null,
          exportsTo ? null,
          evaluate,
        }:
        final.caisson-core.mkConfiguration {
          inherit type perSystem;
          record =
            (if defaultPkgs == null then { } else { inherit defaultPkgs; })
            // (if exportsTo == null then { } else { inherit exportsTo; });
          evaluate =
            view:
            let
              evaluated = evaluate view;
              config = evaluated.config or evaluated.value.config;
            in
            {
              inherit (evaluated) value;
              outputs = (evaluated.outputs or { }) // {
                exports = config.caisson.exports;
              };
              children = view.lib.caisson.integrations.childrenOf config;
              # What the modules register for the configurations
              # beneath (`caisson.forChildren`). Each module is keyed
              # by where it is registered, so a selection that names
              # it more than once imports it once.
              forChildren = {
                modules = builtins.mapAttrs (
                  class:
                  builtins.mapAttrs (
                    name: module: {
                      key = "caisson.forChildren.modules.${class}.${name} of ${type} ${view.manifest.name or ""}";
                      imports = [ module ];
                    }
                  )
                ) config.caisson.forChildren.modules;
                defaultModuleImports = builtins.mapAttrs (_: selection: [
                  selection
                ]) config.caisson.forChildren.defaultModuleImports;
                defaultPkgs = config.caisson.forChildren.defaultPkgs;
                systems = config.caisson.forChildren.systems;
              };
            };
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

      # An integration that owns a module class, declared. The
      # declaration carries the entry points as pattern functions,
      # `mkConfiguration` and its `WithEcosystemArgs` twin, and the
      # result holds `namespace`, the value of `lib.caisson.<name>` (the
      # entry points, the registration form `mkModule` bound to the
      # class, and whatever `extra` adds beside them: variants,
      # adapters, the composition an alt over the class reads), and
      # `classes`, the declaration of the class for the index, so
      # `mkModules` registers the class through this integration. The
      # overlay file writes both under their keys, since an overlay's
      # output attribute names must not depend on `final`:
      #
      #   overlay = final: prev:
      #     let integration = final.caisson.integrations.mkIntegration { ... }; in
      #     contributeClasses prev integration.classes
      #     // { caisson = (prev.caisson or { }) // { nixos = integration.namespace; }; };
      mkIntegration =
        {
          name,
          class,
          mkConfiguration,
          mkConfigurationWithEcosystemArgs,
          extra ? { },
        }:
        let
          mkModule = final.caisson-core.mkModule class;

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
              builtins.mapAttrs (_: _: mkConfiguration args) (final.caisson-core.configs.${class} or { })
          ) (builtins.removeAttrs (functionArgs mkConfiguration) [ "configModule" ]);
        in
        {
          namespace = {
            inherit
              mkConfiguration
              mkConfigurationWithEcosystemArgs
              mkModule
              ;
          }
          // (if findsModuleByName then { inherit mkConfigurations; } else { })
          // extra;
          classes = {
            ${class} = {
              integration = name;
              inherit mkModule;
            };
          };
        };

      # The integrations a configuration may be declared of: those
      # that own a class, by the class index. caisson's core module
      # declares `caisson.<integration>.configurations` for each.
      names =
        let
          owners = builtins.map (class: class.integration) (builtins.attrValues final.caisson-core.classes);
        in
        builtins.filter (name: name != "caisson-core") (unique owners);

      # The configurations an evaluated configuration declares beneath
      # it, by integration and then name, as the `children` an
      # integration's `evaluate` returns: the values of its
      # `caisson.<integration>.configurations` options, which finalize
      # each entry when read. An integration with none declared is left
      # out.
      childrenOf =
        config:
        filterAttrs (_: declared: declared != { }) (
          genAttrs names (name: config.caisson.${name}.configurations)
        );

      isManifest = value: builtins.isAttrs value && (value._type or null) == "caisson-manifest";

      # How a configuration is published: the `exportsTo` its
      # manifest records, or null for a configuration that is not
      # published under a name (structural, flake-parts).
      exportsToOf = manifest: manifest.exportsTo or null;

      showPath =
        path:
        builtins.concatStringsSep " / " (builtins.map (segment: "${segment.type} ${segment.name}") path);

      # The entry of a configuration that is passed up under `prefix`,
      # whose last segment holds the name it is passed up under: the
      # output attribute set and the value its `exportsTo` gives, and
      # its path, on which the name its `exportsTo` gives, where it
      # gives one, stands in place of that name.
      entryOf =
        prefix: manifest:
        let
          exportsTo = exportsToOf manifest;
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
      # `{ type, name }` segments. A configuration evaluated at a
      # system has that system above its name on the path. `selected`
      # is what each integration's `exported` selected, by integration
      # and then name, each value a manifest or the evaluations of a
      # configuration by system. A configuration whose manifest
      # records `exportsTo` is an entry, made here, where the name it
      # is passed up under is known, from what the manifest records;
      # and every configuration contributes the entries it passes up
      # in turn, with its segments in front. An entry carries all a
      # top needs to publish it.
      entriesOf =
        selected:
        builtins.concatMap (
          integration:
          builtins.concatMap (
            name:
            let
              finalized = selected.${integration}.${name};
              segment = {
                type = integration;
                inherit name;
              };
              beneath =
                if isManifest finalized then
                  [
                    {
                      prefix = [ segment ];
                      manifest = finalized;
                    }
                  ]
                else
                  builtins.map (system: {
                    prefix = [
                      {
                        type = "system";
                        name = system;
                      }
                      segment
                    ];
                    manifest = finalized.${system};
                  }) (builtins.attrNames finalized);
            in
            builtins.concatMap (
              { prefix, manifest }:
              (if exportsToOf manifest == null then [ ] else [ (entryOf prefix manifest) ])
              ++ builtins.map (entry: entry // { path = prefix ++ entry.path; }) (
                manifest.outputs.exports.configurations or [ ]
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
      publish =
        entries:
        let
          attrsets = unique (builtins.map (entry: entry.attrset) entries);
          publishIn =
            attrset:
            let
              members = builtins.filter (entry: entry.attrset == attrset) entries;
              names = builtins.map displayName (
                final.caisson-core.elide (builtins.map (entry: entry.path) members)
              );
              named = zipListsWith (name: entry: { inherit name entry; }) names members;
              clashing = builtins.filter (
                name: builtins.length (builtins.filter (other: other == name) names) > 1
              ) (unique names);
            in
            if clashing != [ ] then
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
                  inherit (item.entry) value;
                }) named
              );
        in
        genAttrs attrsets publishIn;

      # What a tool reads from a top that is a configuration evaluated
      # at a system, given its evaluations by system. They are named
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
          extra ? { },
        }:
        assert builtins.isAttrs over && over ? mkModule;
        {
          inherit mkConfiguration mkConfigurationWithEcosystemArgs;
        }
        // extra;

    in
    {
      caisson = (prev.caisson or { }) // {
        integrations = ((prev.caisson or { }).integrations or { }) // {
          inherit
            childrenOf
            displayName
            entriesOf
            mkEvaluation
            names
            publish
            topValue
            resolveEcosystemSrc
            mkIntegration
            mkAltIntegration
            frameworkModules
            mkModuleConfiguration
            moduleImportsOf
            pkgSetOf
            pkgSetsAt
            ;
          coreModules = select "core";
          defaultModuleImports = select "default";
        };
      };
    };

}
