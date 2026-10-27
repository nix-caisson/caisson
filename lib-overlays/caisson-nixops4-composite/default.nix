# SPDX-License-Identifier: MIT
#
# The caisson-nixops4-composite integration: a composite of a NixOps4
# deployment, a component that holds further components as its
# members. The root component NixOps4 deploys is the outermost
# composite, declared under the name `nixops4`, for the output it
# fills.
#
# A composite is a deferred configuration (caisson-core's
# `mkDeferredConfiguration`): it is evaluated when NixOps4 deploys,
# with its args, and NixOps4 evaluates it again each time the outputs
# of a resource become known. Its args are `outputValues`, the outputs
# of its members by member name as NixOps4 passes them, and
# `resourceProviderSystem`, the system NixOps4 runs providers on. Its
# members are the caisson-nixops4-composite and
# caisson-nixops4-resource configurations declared beneath it. It
# finalizes each member with that member's part of its args, so its
# manifest holds the members' manifests as its children.
#
# A composite declares providers, as NixOps4's components do, with
# NixOps4's own `providers` option, and its module reads its members'
# outputs through the `members` module argument: for each member, its
# `outputs` and its `absoluteMemberPath`, both from the args and the
# names the members are declared under. A member's config is not
# reachable through it. A composite has no `type` and no resource
# options: a composite that sets them is refused where it sets them, as
# an undeclared option.
#
# What a composite publishes to NixOps4 is its export: its members'
# exports, by name, as NixOps4's `_export` of a composite holds them.
# The root composite is published as the `nixops4` output NixOps4's
# command reads: `_type`, `rootFunction` and `getProviders`, as
# NixOps4's `mkRoot` returns them.
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
    # The resource integration, whose helpers this integration builds
    # on.
    ((mkLibOverlay ../caisson-nixops4-resource) // { key = "caisson-nixops4-resource"; })
  ];

  overlay =
    final: prev:
    let
      resources = final.caisson.caisson-nixops4-resource;
      inherit (resources) showPath;
      context = "lib.caisson.caisson-nixops4-composite";
      compositeType = "caisson-nixops4-composite";
      resourceType = "caisson-nixops4-resource";

      # The members of a composite at `path`, by name, from its
      # evaluation: the composites and resources declared beneath it,
      # each the entry caisson-core holds for a deferred child. Their
      # names are readable in the childless view too, and the entries
      # only in the full evaluation. A name declared as both is refused,
      # since NixOps4 holds one member under a name.
      memberEntriesOf =
        path: config:
        let
          composites = config.caisson.${compositeType}.configurations;
          members = config.caisson.${resourceType}.configurations;
          both = builtins.attrNames (builtins.intersectAttrs composites members);
        in
        if both == [ ] then
          composites // members
        else
          throw ''
            ${context}: the composite at ${showPath path} declares
            ${builtins.concatStringsSep ", " (builtins.map (n: "`${n}`") both)} both as a composite and as a
            resource; a member is one or the other.
          '';

      # The `members` module argument of a native composite: for each
      # member, its outputs from the composite's args and its member
      # path from its name.
      nativeMembersArg =
        {
          args,
          path,
          entries,
          ...
        }:
        builtins.mapAttrs (member: _: {
          outputs = args.outputValues.${member};
          absoluteMemberPath = path ++ [ member ];
        }) entries;

      # The root of a deployment, as NixOps4's `mkRoot` returns it, over
      # the entry of the root composite. `rootFunction` finalizes the
      # root with the args NixOps4 passes and returns its export.
      # `getProviders` finalizes it with the deploying system alone and
      # builds the providers the root declares, as the `getProviders`
      # of NixOps4 does; reading an output there fails, as it does
      # upstream. Providers declared beneath the root are not
      # collected, as upstream collects none of them either.
      rootOf = entry: {
        _type = "nixops4Component";
        rootFunction =
          {
            outputValues,
            resourceProviderSystem,
            ...
          }:
          (entry.finalize {
            args = { inherit outputValues resourceProviderSystem; };
            argsSource = _: "NixOps4";
          }).outputs.export;
        getProviders =
          { system }:
          let
            finalized = entry.finalize {
              args.resourceProviderSystem = system;
              argsSource = _: "getProviders for ${system}";
            };
            serializable = builtins.mapAttrs (_: provider: {
              inherit (provider) executable args;
            }) finalized.outputs.providerConfigs;
          in
          (resources.pkgsFor finalized system).writeText "nixops-root-providers" ''
            Store path contents subject to change
            ${builtins.toJSON serializable}
          '';
      };

      # How a composite is published. A composite whose parent is not a
      # composite is a root, published as `nixops4`, an output that
      # holds a single value. A composite beneath another is a member
      # and is not published.
      published = {
        exportsTo = {
          attrset = "nixops4";
          single = true;
          only =
            entry:
            !(builtins.elem (entry.parent.type or null) [
              compositeType
              "nixops4"
            ]);
          value = rootOf;
        };
      };

      # A composite configuration of the module class `class`, evaluated
      # with the modules `baseModules` returns for the NixOps4 source,
      # the member path and the finalized members, and the `members`
      # module argument `membersArg` returns. The native integration
      # evaluates its class with NixOps4's provider declarations and
      # `nativeMembersArg`; the upstream-compatible one builds on this
      # with NixOps4's class and its own modules.
      mkCompositeConfiguration =
        {
          class,
          type ? compositeType,
          baseModules,
          membersArg ? nativeMembersArg,
        }:
        settings:
        let
          # The evaluator's call with the args `args`, on the lib of the
          # view being evaluated: the base modules, the framework
          # modules of the class, the selection and the configuration's
          # module, with the composition's pinned sources as the
          # `inputs` special argument and the deploying system as
          # `resourceProviderSystem`, as NixOps4 passes it.
          # `ecosystemArgs` is merged over the call last.
          evaluate =
            args:
            { lib, manifest }:
            let
              selection = lib.caisson.integrations;
              path = resources.absoluteMemberPathOf manifest;
              src = resources.ecosystemSrcOf {
                explicit = settings.ecosystemSrc or null;
                inherit manifest;
              };
              registry = lib.caisson.modules.${class} or { };
              frameworkModules = selection.frameworkModules class registry;
              moduleImports = selection.moduleImportsOf class { inherit lib manifest; } settings;
              name = manifest.name or null;
              configModule = selection.configModuleOf {
                inherit lib name class;
                configModule = settings.configModule or null;
              };
              # The members, by name. The names come from `naming`, and
              # each entry comes from the evaluation, so the composite's
              # module may read `members` wherever it does not decide
              # which members there are.
              declared = memberEntriesOf path evaluated.config;
              entries = builtins.mapAttrs (member: _: declared.${member}) (memberEntriesOf path naming.config);
              # The members, each finalized once with its part of the
              # composite's args, from the full evaluation. The
              # childless view finalizes none.
              finalized =
                if manifest.childless then
                  { }
                else
                  builtins.mapAttrs (
                    member: entry:
                    entry.finalize {
                      args = {
                        outputValues = args.outputValues.${member};
                        inherit (args) resourceProviderSystem;
                      };
                      argsSource = _: "the composite at ${showPath path}";
                    }
                  ) entries;
              ofType = memberType: final.filterAttrs (_: member: member.type == memberType) finalized;
              # The modules of an evaluation in which the `members`
              # module argument is what `members` returns for the
              # evaluation's config, and the base modules receive
              # `finalized`.
              modulesWith =
                { members, finalized }:
                baseModules { inherit src path finalized; }
                ++ [
                  (selection.caissonModule {
                    key = "caisson.${type}.members";
                    file = "caisson-${type}:members";
                    module =
                      { config, ... }:
                      {
                        _module.args.members = members config;
                      };
                  })
                ]
                ++ frameworkModules
                ++ moduleImports registry
                ++ (if configModule == null then [ ] else [ configModule ]);
              evaluationOf =
                modules:
                lib.evalModules (
                  {
                    inherit class modules;
                    specialArgs = {
                      inherit lib;
                      inputs = manifest.sources;
                      inherit (args) resourceProviderSystem;
                    }
                    // (if (settings.specialArgs or null) != null then settings.specialArgs else { });
                  }
                  // (if (settings.ecosystemArgs or null) != null then settings.ecosystemArgs else { })
                );
              moduleList = modulesWith {
                inherit finalized;
                members =
                  config:
                  membersArg {
                    inherit
                      args
                      path
                      entries
                      config
                      ;
                  };
              };
              evaluated = evaluationOf moduleList;
              # The evaluation that decides which members there are. The
              # members and their outputs fail there when they are read,
              # with an error that names the composite, since the names
              # of the members must be known before any member is
              # finalized.
              naming = evaluationOf (modulesWith {
                members = _: membersUnknown;
                finalized = membersUnknown;
              });
              membersUnknown = throw ''
                ${context}: the composite at ${showPath path} reads its members, or their
                outputs, where it decides which members it has. Which members a composite
                has, and whether each is a composite or a resource, must not depend on its
                members or on their outputs.
              '';
              # The member paths of the resources in the tree of this
              # composite that hold state, each once.
              stateResources = final.unique (
                builtins.concatMap (
                  member:
                  if member.type == compositeType then
                    member.outputs.stateResources
                  else
                    let
                      state = member.outputs.export.resource.state;
                    in
                    if state == null then [ ] else [ state ]
                ) (builtins.attrValues finalized)
              );
            in
            {
              value = evaluated;
              ecosystems.nixops4 = resources.ecosystemAccountOf {
                explicit = settings.ecosystemSrc or null;
                inherit manifest;
              };
              modules = moduleList;
              # The finalized members, by integration and then name, so
              # the manifest holds their manifests.
              children = final.filterAttrs (_: members: members != { }) {
                ${compositeType} = ofType compositeType;
                ${resourceType} = ofType resourceType;
              };
              outputs = {
                inherit path stateResources;
                # What NixOps4 reads of the composite.
                export.members = builtins.mapAttrs (_: member: member.outputs.export) finalized;
                # The providers it declares, which `getProviders` builds
                # for the root.
                providerConfigs = evaluated.config.providers;
              };
              # The deploying system, and the outputs of the members, by
              # member name, as each member names them.
              argsNeeded = {
                resourceProviderSystem = resources.systemArg;
                outputValues = builtins.mapAttrs (_: member: member.argsNeeded.outputValues) finalized;
              };
            }
            // (
              # The root gives a program that reads the outputs NixOps4
              # recorded, when a resource of the deployment holds state.
              if path == [ ] then
                {
                  discoverArgs =
                    { system }:
                    if stateResources == [ ] then
                      null
                    else
                      resources.discoverArgsOf {
                        inherit manifest src system;
                        stateResources = builtins.map (builtins.concatStringsSep ".") stateResources;
                      };
                }
              else
                { }
            );
        in
        final.caisson-core.mkDeferredConfiguration {
          inherit type class;
          record = published // {
            exportsToPosition = final.caisson.integrations.positionOf (
              builtins.unsafeGetAttrPos "exportsTo" published
            );
          };
          configuration =
            {
              name,
              parent,
              args,
            }:
            final.caisson.integrations.mkModuleConfiguration {
              selection = {
                inherit class;
                args = settings;
              };
              inherit type;
              defaultPkgs = settings.defaultPkgs or null;
              evaluate = evaluate args;
            } { inherit name parent; };
        };

      configuration = mkCompositeConfiguration {
        class = compositeType;
        baseModules =
          { src, ... }:
          [
            # NixOps4's `providers` option, whose resource types the
            # composite writes into its members' `type`.
            (resources.componentModule src "provider-declarations")
          ];
      };

      integration = final.caisson.integrations.mkIntegration {
        name = compositeType;
        class = compositeType;
        # What these return is a deferred configuration, a function of
        # `{ name, parent, args }`. Declared under the name `nixops4`
        # where no composite holds it, it is the root, finalized when
        # NixOps4 calls `rootFunction`. Declared under
        # `caisson.caisson-nixops4-composite.configurations.<name>` of
        # a composite, it is a member, finalized by that composite.
        mkConfiguration =
          {
            # The composite's module: its providers and members. When
            # absent, the configuration registered under the
            # configuration's name, if any.
            configModule ? null,
            # The package set the deployment runs on, for the composite
            # and its members: a function that receives the package
            # sets available, by package config name, and returns the
            # set to run on.
            defaultPkgs ? null,
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
          }@settings:
          configuration settings;
        # The same arguments and `ecosystemArgs`, the evaluator's
        # arguments merged over the composed call last.
        mkConfigurationWithEcosystemArgs =
          {
            configModule ? null,
            defaultPkgs ? null,
            ecosystemSrc ? null,
            moduleImports ? null,
            extraModuleImports ? null,
            specialArgs ? null,
            ecosystemArgs ? null,
          }@settings:
          configuration settings;
        # What the upstream-compatible integration builds on.
        extra = {
          inherit mkCompositeConfiguration;
        };
      };
    in
    {
      caisson = (prev.caisson or { }) // {
        caisson-nixops4-composite = integration.namespace;
      };
    };

}
