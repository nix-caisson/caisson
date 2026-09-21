# SPDX-License-Identifier: MIT
#
# What an integration is written from: the functions every integration
# overlay shares, under `lib.caisson.integrations`. Each integration
# imports this overlay by key, so composing any one of them composes
# this, and reads the functions through `final`. `mkIntegration` and
# `mkAltIntegration` generate an integration from its declaration
# (design section 8) out of these pieces.
#
#   checkArgs            the closed signature of an entry point: every
#                        integration takes exactly the caisson-shaped
#                        arguments (configModule, moduleImports,
#                        specialArgs, pkgSets, ecosystemSrc, and the
#                        few of one target) and composes the evaluator's
#                        call from them. Nothing else is forwarded: an
#                        evaluator argument handed in directly would be
#                        silently overwritten, silently dropped, or
#                        surface as a conflict deep inside the
#                        evaluator. The `...WithEcosystemArgs` twin of
#                        each entry point is the way to the evaluator's
#                        full surface: the same arguments plus
#                        `ecosystemArgs`, merged over the composed call
#                        verbatim, last.
#   resolveEcosystemSrc  the layered ecosystem-source resolution:
#                        caisson-core's `resolve` (the explicit
#                        argument, then the composition's declared
#                        `defaultEcosystemSrc.<name>`, then an input
#                        with exactly the declared name), with the miss
#                        interpreted here, where the integration knows
#                        what to say; the resolver itself never formats
#                        a message, because a miss is the plain value
#                        null. The declarations and inputs are read from
#                        the composition's manifest; a manifest-less
#                        composition resolves only the explicit
#                        argument.
#   coreModules          the two selections every integration draws
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

      checkArgs =
        {
          # the entry point, for the message
          context,
          # the argument names it takes
          accepted,
          # per-name pointers for the common mistakes (an evaluator
          # name where a caisson name exists)
          hints ? { },
          # the twin's name, or null when checking the twin itself
          open ? null,
        }:
        args:
        let
          unknown = builtins.filter (name: !(builtins.elem name accepted)) (builtins.attrNames args);
          name = builtins.head unknown;
          message =
            if hints ? ${name} then
              "${context} does not accept `${name}`: ${hints.${name}}"
            else if open != null then
              "${context} does not accept `${name}`; it takes ${builtins.concatStringsSep ", " accepted}. The evaluator's arguments are available through ${open}, in `ecosystemArgs`."
            else
              "${context} does not accept `${name}`; it takes ${builtins.concatStringsSep ", " accepted}. Evaluator arguments go in `ecosystemArgs`.";
        in
        if unknown == [ ] then args else throw message;

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
            inputs = manifest.inputs or { };
          };
        in
        if resolved != null then
          resolved
        else
          throw ''
            ${context}: no ${name} ecosystem source. Pass `ecosystemSrc`
            explicitly, declare `defaultEcosystemSrc.${name}` in the mkLib call,
            or name the source `${name}` in the inputs passed to mkLib.
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

      # The arguments every entry point takes; a declaration adds the
      # few of its own.
      commonAccepted = [
        "ecosystemSrc"
        "pkgSets"
        "configModule"
        "moduleImports"
        "specialArgs"
      ];
      commonHints = {
        modules = "pass the configuration's module as `configModule`; registered class modules are selected with `moduleImports`.";
      };

      # The entry points a declaration generates: `mkConfiguration`,
      # which checks the arguments against the closed signature,
      # composes the evaluator's call and evaluates it, and the
      # `WithEcosystemArgs` twin, which merges `ecosystemArgs` over the
      # composed call verbatim, last. `compose` takes the checked
      # arguments and returns an attrset holding `ecosystemArgs`, the
      # evaluator's call as composed, beside whatever `evaluate` needs;
      # `evaluate` takes that attrset and the call to make.
      mkEntryPoints =
        {
          name,
          accepted,
          hints,
          compose,
          evaluate,
        }:
        let
          context = "lib.caisson.${name}";
          allAccepted = commonAccepted ++ accepted;
          allHints = commonHints // hints;
          check = checkArgs {
            context = "${context}.mkConfiguration";
            accepted = allAccepted;
            hints = allHints;
            open = "${context}.mkConfigurationWithEcosystemArgs";
          };
          checkOpen = checkArgs {
            context = "${context}.mkConfigurationWithEcosystemArgs";
            accepted = allAccepted ++ [ "ecosystemArgs" ];
            hints = allHints;
          };
        in
        {
          mkConfiguration =
            rawArgs:
            let
              composed = compose (check rawArgs);
            in
            evaluate composed composed.ecosystemArgs;
          mkConfigurationWithEcosystemArgs =
            rawArgs:
            let
              args = checkOpen rawArgs;
              composed = compose args;
            in
            evaluate composed (composed.ecosystemArgs // (args.ecosystemArgs or { }));
        };

      # An integration that owns a module class, declared. The result
      # holds `namespace`, the value of `lib.caisson.<name>` (the entry
      # points, the registration form `mkModule` bound to the class,
      # and whatever `extra` adds beside them: variants, adapters, the
      # composition an alt over the class reads), and `classes`, the
      # declaration of the class for the index, so `mkModules`
      # registers the class through this integration. The overlay
      # file writes both under their keys, since an overlay's output
      # attribute names must not depend on `final`:
      #
      #   overlay = final: prev:
      #     let integration = final.caisson.integrations.mkIntegration { ... }; in
      #     contributeClasses prev integration.classes
      #     // { caisson = (prev.caisson or { }) // { nixos = integration.namespace; }; };
      mkIntegration =
        {
          name,
          class,
          accepted ? [ ],
          hints ? { },
          compose,
          evaluate,
          extra ? { },
        }:
        let
          mkModule = final.caisson-core.mkModule class;
        in
        {
          namespace =
            mkEntryPoints {
              inherit
                name
                accepted
                hints
                compose
                evaluate
                ;
            }
            // {
              inherit mkModule;
            }
            // extra;
          classes = {
            ${class} = {
              integration = name;
              inherit mkModule;
            };
          };
        };

      # An integration that evaluates a class another integration
      # owns, declared: `over` is the owning integration, reached
      # through the lib (`final.caisson.nixos`), and the class and its
      # registration form belong to that integration; `compose` builds
      # on the composition that integration publishes, so the two
      # evaluators cannot express different configurations from the
      # same arguments. The result is the value of `lib.caisson.<name>`:
      # the entry points and `extra`, no `mkModule`, and no class
      # declaration.
      mkAltIntegration =
        {
          name,
          over,
          accepted ? [ ],
          hints ? { },
          compose,
          evaluate,
          extra ? { },
        }:
        assert builtins.isAttrs over && over ? mkModule;
        mkEntryPoints {
          inherit
            name
            accepted
            hints
            compose
            evaluate
            ;
        }
        // extra;

    in
    {
      caisson = (prev.caisson or { }) // {
        integrations = ((prev.caisson or { }).integrations or { }) // {
          inherit
            checkArgs
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
