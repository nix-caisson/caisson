# SPDX-License-Identifier: MIT
#
# The caisson-nixops4-composite integration: a composite of a NixOps4
# deployment, a component that holds further components as its
# members. The root component NixOps4 deploys is the outermost
# composite, declared under the name `root` beneath a caisson-nixops4
# configuration.
#
# A composite is a deferred configuration (caisson-core's
# `mkDeferredConfiguration`): it is evaluated when NixOps4 deploys,
# with the args its parent gives it, and NixOps4 evaluates it again
# each time the outputs of a resource become known. Its members are the
# caisson-nixops4-composite and caisson-nixops4-resource configurations
# declared beneath it, deferred children in turn, which it finalizes
# with their part of its args (`memberArgs` of caisson-nixops4).
#
# A composite declares providers, as NixOps4's components do, with
# NixOps4's own `providers` option, and its module reads its members'
# outputs through the `members` module argument. It has no `type` and
# no resource options: a composite that sets them is refused where it
# sets them, as an undeclared option.
#
# What a composite publishes to NixOps4 is its export: its members'
# exports, by name, as NixOps4's `_export` of a composite holds them.
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
    # The declaration, whose helpers this integration builds on.
    ((mkLibOverlay ../caisson-nixops4) // { key = "caisson-nixops4"; })
  ];

  overlay =
    final: prev:
    let
      nixops4 = final.caisson.caisson-nixops4;
      context = "lib.caisson.caisson-nixops4-composite";
      compositeType = "caisson-nixops4-composite";
      resourceType = "caisson-nixops4-resource";

      # The member path of a component, as NixOps4 writes it.
      showPath = path: if path == [ ] then "the root" else builtins.concatStringsSep "." path;

      # The members of a composite, by name, from its full evaluation:
      # the composites and resources declared beneath it, each the entry
      # caisson-core holds for a deferred child. A name declared as both
      # is refused, since NixOps4 holds one member under a name.
      memberEntriesOf =
        deploy: config:
        let
          composites = config.caisson.${compositeType}.configurations;
          resources = config.caisson.${resourceType}.configurations;
          both = builtins.attrNames (builtins.intersectAttrs composites resources);
        in
        if both == [ ] then
          composites // resources
        else
          throw ''
            ${context}: the composite at ${showPath deploy.path} declares
            ${builtins.concatStringsSep ", " (builtins.map (n: "`${n}`") both)} both as a composite and as a
            resource; a member is one or the other.
          '';

      # The members finalized with the args the composite gives them,
      # `memberArgs deploy name`, by name: each a manifest.
      finalizeMembers =
        memberArgs: deploy: entries:
        builtins.mapAttrs (
          name: entry:
          entry.finalize {
            args = memberArgs deploy name;
            argsSource = "the composite at ${showPath deploy.path}";
          }
        ) entries;

      # The output args of a composite's members, as `argsNeeded`
      # declares them: by member name, a resource's outputs, each an
      # arg cacheable where the resource declares it, or a composite's
      # own output args. A member whose outputs cannot be named yet,
      # because naming them waits for an output, is left out, and a tool
      # asks again once it has that output.
      outputArgsOf =
        members:
        builtins.mapAttrs (
          _: member:
          let
            named =
              if member.type == resourceType then
                builtins.mapAttrs (
                  output: _:
                  final.caisson-core.mkArg {
                    cacheable = builtins.elem output member.outputs.cacheableOutputs;
                    description = "An output of the resource at ${showPath member.outputs.path}.";
                  }
                ) member.outputs.export.resource.outputsSkeleton
              else
                outputArgsOf member.outputs.members;
            attempt = builtins.tryEval (builtins.deepSeq (builtins.attrNames named) named);
          in
          if attempt.success then named else { }
        ) members;

      # A composite configuration of the module class `class`, evaluated
      # with the modules `baseModules` returns for the NixOps4 source
      # and the args, and the `members` module argument `membersArg`
      # returns. It gives each member the args `memberArgs` returns. The
      # native integration evaluates its class with NixOps4's provider
      # declarations, and the view of the members' outputs as `members`
      # in the composite and in each member; the upstream-compatible one
      # builds on this with NixOps4's class and its own modules.
      compositeWith =
        {
          class,
          type ? compositeType,
          baseModules,
          membersArg ?
            { deploy, ... }:
            nixops4.membersView deploy.path deploy.outputValues,
          memberArgs ? nixops4.memberArgs,
        }:
        args:
        let
          # The evaluator's call, on the lib of the view being
          # evaluated: the base modules, the framework modules of the
          # class, the selection and the configuration's module, with
          # the composition's pinned sources as the `inputs` special
          # argument and the deploying system as
          # `resourceProviderSystem`, as NixOps4 passes it.
          # `ecosystemArgs` is merged over the call last.
          evaluate =
            deploy:
            { lib, manifest }:
            let
              selection = lib.caisson.integrations;
              src = nixops4.ecosystemSrcOf {
                explicit = args.ecosystemSrc or null;
                inherit manifest;
              };
              registry = lib.caisson.modules.${class} or { };
              frameworkModules = selection.frameworkModules class registry;
              moduleImports = selection.moduleImportsOf class { inherit lib manifest; } args;
              name = manifest.name or null;
              configModule = selection.configModuleOf {
                inherit lib name class;
                configModule = args.configModule or null;
              };
              # The members, finalized from the full evaluation; the
              # childless view holds none.
              finalized =
                if manifest.childless then
                  { }
                else
                  finalizeMembers memberArgs deploy (memberEntriesOf deploy evaluated.config);
              membersModule = selection.caissonModule {
                key = "caisson.${type}.members";
                file = "caisson-${type}:members";
                module = {
                  _module.args.members = membersArg {
                    inherit deploy finalized manifest;
                  };
                };
              };
              moduleList =
                baseModules { inherit src deploy; }
                ++ [ membersModule ]
                ++ frameworkModules
                ++ moduleImports registry
                ++ (if configModule == null then [ ] else [ configModule ]);
              evaluated = lib.evalModules (
                {
                  inherit class;
                  specialArgs = {
                    inherit lib;
                    inputs = manifest.sources;
                    inherit (deploy) resourceProviderSystem;
                  }
                  // (if (args.specialArgs or null) != null then args.specialArgs else { });
                  modules = moduleList;
                }
                // (if (args.ecosystemArgs or null) != null then args.ecosystemArgs else { })
              );
            in
            {
              value = evaluated;
              ecosystems.nixops4 = nixops4.ecosystemAccountOf {
                explicit = args.ecosystemSrc or null;
                inherit manifest;
              };
              modules = moduleList;
              outputs = {
                inherit (deploy) path;
                # The members, by name, each finalized with its args.
                members = finalized;
                # What NixOps4 reads of the composite.
                export.members = builtins.mapAttrs (_: member: member.outputs.export) finalized;
                # The providers it declares, which `getProviders` builds
                # for the root.
                providerConfigs = evaluated.config.providers;
              };
            };

          configurationFor =
            deploy:
            final.caisson.integrations.mkModuleConfiguration {
              selection = {
                inherit class args;
              };
              inherit type;
              evaluate = evaluate deploy;
            };
        in
        final.caisson-core.mkDeferredConfiguration {
          inherit type class;
          # The deploying system, and the outputs of the members, which
          # depend on the members the composite declares, so on the args
          # known so far.
          argsNeeded =
            {
              name,
              parent,
              args,
            }:
            let
              manifest = configurationFor (nixops4.deployOf name args) { inherit name parent; };
            in
            {
              resourceProviderSystem = nixops4.systemArg;
              outputValues = outputArgsOf manifest.outputs.members;
            };
          configuration =
            {
              name,
              parent,
              args,
            }:
            configurationFor (nixops4.deployOf name args) { inherit name parent; };
        };

      configuration = compositeWith {
        class = compositeType;
        baseModules =
          { src, ... }:
          [
            # NixOps4's `providers` option, whose resource types the
            # composite writes into its members' `type`.
            (nixops4.componentModule src "provider-declarations")
          ];
      };

      integration = final.caisson.integrations.mkIntegration {
        name = compositeType;
        class = compositeType;
        # What these return is a deferred configuration, a function of
        # `{ name, parent, args }`: the composite that declares it under
        # `caisson.caisson-nixops4-composite.configurations.<name>`, or
        # the caisson-nixops4 configuration for `root`, finalizes it
        # when NixOps4 deploys.
        mkConfiguration =
          {
            # The composite's module: its providers and members. When
            # absent, the configuration registered under the
            # configuration's name, if any.
            configModule ? null,
            # The NixOps4 flake; resolved from the composition's
            # declarations when absent.
            ecosystemSrc ? null,
            # The selection over the caisson-nixops4-composite class of
            # the registry, replacing the default of the class.
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
            moduleImports ? null,
            extraModuleImports ? null,
            specialArgs ? null,
            ecosystemArgs ? null,
          }@args:
          configuration args;
        # What the upstream-compatible integration builds on.
        extra = {
          inherit compositeWith showPath;
        };
      };
    in
    {
      caisson = (prev.caisson or { }) // {
        caisson-nixops4-composite = integration.namespace;
      };
    };

}
