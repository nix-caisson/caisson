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
{ ... }:
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

      # The evaluations of a per-system configuration with the system
      # left out where nothing needs it: the evaluation itself where
      # the configuration has exactly one, and the evaluations by
      # system otherwise. The tree always holds them by system
      # (`children.system`); this is the step that drops the system
      # for a reader that addresses the configuration alone.
      elideSystems =
        manifest:
        let
          evaluations = manifest.children.system;
          systems = builtins.attrNames evaluations;
        in
        if builtins.length systems == 1 then evaluations.${builtins.head systems} else evaluations;

      # What a tool reads from a per-system configuration that is a
      # top: the evaluated value where the configuration has exactly
      # one evaluation, and the evaluated values by system otherwise.
      topValue =
        manifest:
        let
          elided = elideSystems manifest;
        in
        if (elided._type or null) == "caisson-manifest" then
          elided.value
        else
          builtins.mapAttrs (_: evaluation: evaluation.value) elided;

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
            elideSystems
            mkEvaluation
            names
            topValue
            resolveEcosystemSrc
            mkIntegration
            mkAltIntegration
            ;
          coreModules = select "core";
          defaultModuleImports = select "default";
        };
      };
    };

}
