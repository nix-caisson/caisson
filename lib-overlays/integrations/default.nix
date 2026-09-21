# SPDX-License-Identifier: MIT
#
# What an integration is written from: the functions every integration
# overlay shares, under `lib.caisson.integrations`. Each integration
# imports this overlay by key, so composing any one of them composes
# this, and reads the functions through `final`. When `mkIntegration`
# generates integrations from declarations (design section 8), these
# are the pieces it generates them from.
#
#   checkArgs            the closed signature of an entry point: every
#                        integration takes exactly the caisson-shaped
#                        arguments (configModule, moduleImports,
#                        specialArgs, pkgSets, ecosystemSrc, and a
#                        target's own few) and composes the evaluator's
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
              "${context} does not accept `${name}`; it takes ${builtins.concatStringsSep ", " accepted}. The evaluator's own arguments are available through ${open}, in `ecosystemArgs`."
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

    in
    {
      caisson = (prev.caisson or { }) // {
        integrations = ((prev.caisson or { }).integrations or { }) // {
          inherit checkArgs resolveEcosystemSrc;
          coreModules = select "core";
          defaultModuleImports = select "default";
        };
      };
    };

}
