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
#                        Every such configuration holds configurations
#                        of any integration beneath it, and this is
#                        where that is written: the configurations its
#                        modules declare are its children, and what
#                        they export is passed up through it. An
#                        integration writes neither.
{ closure-lib, ... }:
{

  imports = [ ];

  overlay =
    final: prev:
    let

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
      # What every such configuration has is added here: the
      # configurations its modules declare under
      # `caisson.<integration>.configurations`, of any integration,
      # are its children, and `caisson.exports`, which carries what
      # they pass up, is among its outputs.
      mkModuleConfiguration =
        {
          type,
          perSystem ? false,
          evaluate,
        }:
        final.caisson-core.mkConfiguration {
          inherit type perSystem;
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
          # Where a top publishes the configurations of this
          # integration, and what of each: `attrset`, the output
          # attribute set (`nixosConfigurations`), and `value`, the
          # function from a configuration's manifest to what is
          # published. Absent for an integration whose configurations
          # are not published under a name.
          exportsTo ? null,
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
          findsModuleByName = (final.functionArgs mkConfiguration).configModule or false;
          mkConfigurations = final.setFunctionArgs (
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
          ) (builtins.removeAttrs (final.functionArgs mkConfiguration) [ "configModule" ]);
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
          // (if exportsTo == null then { } else { inherit exportsTo; })
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
        builtins.filter (name: name != "caisson-core") (final.unique owners);

      # The configurations an evaluated configuration declares beneath
      # it, by integration and then name, as the `children` an
      # integration's `evaluate` returns: the values of its
      # `caisson.<integration>.configurations` options, which finalize
      # each entry when read. An integration with none declared is left
      # out.
      childrenOf =
        config:
        final.filterAttrs (_: declared: declared != { }) (
          final.genAttrs names (name: config.caisson.${name}.configurations)
        );

      isManifest = value: builtins.isAttrs value && (value._type or null) == "caisson-manifest";

      # Where the configurations of an integration are published, and
      # what of each: the `exportsTo` the integration declares, or null
      # for an integration whose configurations are not published
      # under a name (structural, flake-parts).
      exportsToOf = manifest: (final.caisson.${manifest.type} or { }).exportsTo or null;

      # A published name, from the segments `caisson-core.elide` keeps
      # of a path: the segments in path order, separated by `/`. Every
      # name caisson publishes is written here.
      displayName = builtins.concatStringsSep "/";

      # The entries a configuration passes up for the configurations
      # declared beneath it at any depth: for each, its manifest and
      # its path from here, a list of `{ type, name }` segments. A
      # configuration evaluated at a system has that system above its
      # name on the path. `selected` is what each integration's
      # `exported` selected, by integration and then name, each value a
      # manifest or the evaluations of a configuration by system. A
      # configuration whose integration declares `exportsTo` is an
      # entry, and every configuration contributes the entries it
      # passes up in turn, with its segments in front.
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
              (
                if exportsToOf manifest == null then
                  [ ]
                else
                  [
                    {
                      path = prefix;
                      inherit manifest;
                    }
                  ]
              )
              ++ builtins.map (entry: entry // { path = prefix ++ entry.path; }) (
                manifest.outputs.exports.configurations or [ ]
              )
            ) beneath
          ) (builtins.attrNames selected.${integration})
        ) (builtins.attrNames selected);

      # What a top publishes of the entries passed up to it, by the
      # output attribute set each entry's integration declares and
      # then name. Within an attribute set the names come from
      # `caisson-core.elide` over the paths: a name that is alone stays
      # bare, and names that collide gain the segments that tell them
      # apart. Entries that still share a name are refused, with their
      # paths.
      publish =
        entries:
        let
          attrsetOf = entry: (exportsToOf entry.manifest).attrset;
          attrsets = final.unique (builtins.map attrsetOf entries);
          showPath =
            path:
            builtins.concatStringsSep " / " (builtins.map (segment: "${segment.type} ${segment.name}") path);
          publishIn =
            attrset:
            let
              members = builtins.filter (entry: attrsetOf entry == attrset) entries;
              names = builtins.map displayName (
                final.caisson-core.elide (builtins.map (entry: entry.path) members)
              );
              named = final.zipListsWith (name: entry: { inherit name entry; }) names members;
              clashing = builtins.filter (
                name: builtins.length (builtins.filter (other: other == name) names) > 1
              ) (final.unique names);
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
                  value = (exportsToOf item.entry.manifest).value item.entry.manifest;
                }) named
              );
        in
        final.genAttrs attrsets publishIn;

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
          names = builtins.map (segments: displayName (final.init segments)) kept;
        in
        if names == [ "" ] then
          evaluations.${builtins.head systems}.value
        else
          builtins.listToAttrs (
            final.zipListsWith (name: system: {
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
            ;
          coreModules = select "core";
          defaultModuleImports = select "default";
        };
      };
    };

}
