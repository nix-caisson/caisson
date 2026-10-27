# SPDX-License-Identifier: MIT
#
# The nixops4 integration, the upstream-compatible one: it takes the
# modules of a root component as NixOps4 users write them for NixOps4's
# `mkRoot`, of NixOps4's class `nixops4Component`, and caisson evaluates
# every component of the deployment. The native integrations,
# caisson-nixops4-composite and caisson-nixops4-resource, take
# caisson's form instead.
#
# A nixops4 configuration is the root composite of the deployment, a
# deferred configuration as a native composite is. Declared under the
# name `nixops4`, for the output it fills, it is published as the
# native root is. Every component is evaluated with NixOps4's class
# name, so a module that sets `_class = "nixops4Component"` loads, and
# with NixOps4's resource, type and providers options.
#
# Upstream declares `members` and the resource options on every
# component and decides which kind a component is when its export is
# read: a component whose `resourceType` is defined is a resource. A
# composite here declares `members` again, as `lazyAttrsOf
# deferredModule`, and decides the same way for each member, with a
# probe evaluation of the member's modules over NixOps4's own base
# modules. A member becomes a caisson-nixops4-resource or a
# caisson-nixops4-composite configuration declared beneath the
# composite, evaluated with the same modules. A member that sets `type`
# and also has members is refused; upstream drops the members.
#
# The `members` module argument and `config.members` are what upstream
# gives: in a composite, the configs of its members, which a composite
# reads to wire one member to another (`members.db.outputs.address`)
# and to name the resource that holds the state of another
# (`state = members.state`); in a resource, nothing. A composite reads
# its members' configs through its full evaluation, so every composite
# sets `unsafeCrossChildReferences` for the class of its members.
#
# A member that imports nixops4-nixos's module gets its `nixos.module`
# evaluated as a caisson NixOS configuration beneath it, rather than by
# the `nixosSystem` call of nixops4-nixos: see the module `nixos` of the
# `nixops4Component` class.
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
    # The native integrations, whose evaluators this one builds on.
    ((mkLibOverlay ../caisson-nixops4-composite) // { key = "caisson-nixops4-composite"; })
    ((mkLibOverlay ../caisson-nixops4-resource) // { key = "caisson-nixops4-resource"; })
  ];

  overlay =
    final: prev:
    let
      composites = final.caisson.caisson-nixops4-composite;
      resources = final.caisson.caisson-nixops4-resource;
      context = "lib.caisson.nixops4";
      upstreamClass = "nixops4Component";
      compositeType = "caisson-nixops4-composite";
      resourceType = "caisson-nixops4-resource";

      # The options every upstream component has beside `members`:
      # NixOps4's resource, type and providers options.
      componentBase = src: [
        (resources.componentModule src "resource")
        (resources.componentModule src "provider-values")
        (resources.componentModule src "provider-declarations")
      ];

      # The modules of a component, as the configuration's module.
      modulesModule =
        modules:
        final.caisson.integrations.caissonModule {
          key = "caisson.nixops4.component";
          file = "caisson-nixops4:component";
          module = {
            imports = modules;
          };
        };

      # Which caisson integration the member `name` of the composite at
      # `path` becomes, by upstream's test: a resource when its
      # `resourceType` is defined, a composite otherwise. The probe
      # evaluates the member's modules over NixOps4's base modules,
      # with the special arguments the member receives.
      kindOf =
        {
          lib,
          src,
          specialArgs,
          path,
        }:
        name: module:
        let
          probe = lib.evalModules {
            class = upstreamClass;
            inherit specialArgs;
            modules = [
              "${src}/nix/component/base-modules.nix"
              module
            ];
          };
          isResource = probe.options.resourceType.isDefined;
          hasMembers = builtins.attrNames probe.config.members != [ ];
        in
        if isResource && hasMembers then
          throw ''
            ${context}: the member ${resources.showPath (path ++ [ name ])} sets `type`, which makes it a
            resource, and declares members, which a resource does not hold.
            NixOps4 would drop them; declare them in a composite instead.
          ''
        else if isResource then
          resourceType
        else
          compositeType;

      # The module of an upstream composite at `path` that declares
      # `members` and turns the modules defined there into the
      # configurations declared beneath it. The members are computed
      # from the definitions of `members`, since its value is the
      # members' configs: in the full evaluation those of the members
      # the composite finalized (`finalized`), and in the childless view
      # those of the full evaluation, which the composite reads through
      # `unsafeCrossChildReferences`.
      membersModule =
        ctx:
        {
          src,
          path,
          finalized,
        }:
        final.caisson.integrations.caissonModule {
          key = "caisson.nixops4.memberComponents";
          file = "caisson-nixops4:memberComponents";
          module =
            {
              lib,
              options,
              inputs,
              resourceProviderSystem,
              ...
            }:
            let
              manifest = lib.caisson-core.evalManifest;
              declared = options.members.type.merge options.members.loc options.members.definitionsWithLocations;
              kinds = builtins.mapAttrs (kindOf {
                inherit lib src path;
                specialArgs = {
                  inherit inputs;
                }
                // ctx.specialArgs
                // {
                  inherit lib resourceProviderSystem;
                };
              }) declared;
              ofKind = kind: lib.filterAttrs (name: _: kinds.${name} == kind) declared;
              members =
                if manifest.childless then
                  let
                    full = manifest.crossChildFull;
                  in
                  (full.children.${compositeType} or { }) // (full.children.${resourceType} or { })
                else
                  finalized;
            in
            {
              options.members = lib.mkOption {
                type = lib.types.lazyAttrsOf lib.types.deferredModule;
                default = { };
                apply = _: builtins.mapAttrs (_: member: member.value.config) members;
                description = ''
                  The member components, by name, as NixOps4 declares them: a
                  member that sets `type` is a resource, any other a composite.
                  Read back, each is the config of that member.
                '';
              };
              # A composite reads its members' configs, through its full
              # evaluation.
              config.caisson.forDirectChildren.unsafeCrossChildReferences.${upstreamClass} = true;
              config.caisson.${compositeType}.configurations = builtins.mapAttrs (
                _: module: compositeOf ctx [ module ]
              ) (ofKind compositeType);
              config.caisson.${resourceType}.configurations = builtins.mapAttrs (
                _: module: resourceOf ctx [ module ]
              ) (ofKind resourceType);
            };
        };

      # The outputs of the resource at `path` that a tool may cache, from
      # the allow-list of the nixops4 configuration.
      cacheableModule =
        ctx: path:
        final.caisson.integrations.caissonModule {
          key = "caisson.nixops4.cacheableOutputs";
          file = "caisson-nixops4:cacheableOutputs";
          module =
            { lib, ... }:
            {
              options.cacheableOutputs = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = ctx.cacheableOutputs.${builtins.concatStringsSep "." path} or [ ];
                readOnly = true;
                description = ''
                  The outputs of this resource a tool may cache, from
                  `cacheableOutputs` of the nixops4 configuration.
                '';
              };
            };
        };

      # A resource holds no members, so its `members` module argument is
      # empty, as it is upstream.
      resourceMembersModule = final.caisson.integrations.caissonModule {
        key = "caisson.nixops4.resourceMembers";
        file = "caisson-nixops4:resourceMembers";
        module = {
          _module.args.members = { };
        };
      };

      # The arguments the native constructors receive for a component
      # with `modules`.
      componentArgs = ctx: modules: {
        configModule = modulesModule modules;
        inherit (ctx) ecosystemSrc specialArgs;
      };

      # An upstream composite of the integration `type`: NixOps4's class
      # and options, `members` declared and its definitions declared
      # beneath as configurations, and `config.members` as its `members`
      # argument. `settings` are further arguments of the native
      # constructor.
      compositeWith =
        {
          type ? compositeType,
          settings ? { },
        }:
        ctx: modules:
        composites.mkCompositeConfiguration {
          inherit type;
          class = upstreamClass;
          baseModules =
            {
              src,
              path,
              finalized,
            }:
            componentBase src
            ++ [
              (membersModule ctx { inherit src path finalized; })
            ];
          membersArg = { config, ... }: config.members;
        } (componentArgs ctx modules // settings);

      compositeOf = compositeWith { };

      # An upstream resource: NixOps4's class and options, and the
      # outputs the configuration allows a tool to cache.
      resourceOf =
        ctx: modules:
        resources.mkResourceConfiguration {
          class = upstreamClass;
          baseModules =
            { src, path }:
            componentBase src
            ++ [
              (cacheableModule ctx path)
              resourceMembersModule
            ];
        } (componentArgs ctx modules);

      # The root composite made from `modules`, as `mkRoot` takes them,
      # of the integration `nixops4`, with the allow-list, the package
      # set and the selection of the configuration.
      configuration =
        settings:
        compositeWith
          {
            type = "nixops4";
            settings = builtins.intersectAttrs {
              defaultPkgs = null;
              moduleImports = null;
              extraModuleImports = null;
              ecosystemArgs = null;
            } settings;
          }
          {
            ecosystemSrc = settings.ecosystemSrc or null;
            specialArgs = if (settings.specialArgs or null) != null then settings.specialArgs else { };
            cacheableOutputs = settings.cacheableOutputs or { };
          }
          (settings.modules or [ ]);

      integration = final.caisson.integrations.mkIntegration {
        name = "nixops4";
        class = upstreamClass;
        # What these return is a deferred configuration, a function of
        # `{ name, parent, args }`: declared under the name `nixops4`,
        # it is the root, finalized when NixOps4 calls `rootFunction`.
        mkConfiguration =
          {
            # The modules of the root component, as NixOps4's `mkRoot`
            # takes them.
            modules ? [ ],
            # Special arguments of every component, as `mkRoot` takes
            # them for the root.
            specialArgs ? null,
            # The outputs a tool that evaluates the deployment ahead of
            # time may cache, by member path, the names from the root
            # joined with `.`: `{ "web.address" = [ "stdout" ]; }`.
            # NixOps4 marks no output as secret, so none is cacheable
            # unless listed.
            cacheableOutputs ? { },
            # The package set the deployment runs on: a function that
            # receives the package sets available, by package config
            # name, and returns the set to run on.
            defaultPkgs ? null,
            # The NixOps4 flake; resolved from the composition's
            # declarations when absent.
            ecosystemSrc ? null,
            # The selection over the nixops4Component class of the
            # registry for the root, replacing the default of the
            # class.
            moduleImports ? null,
            # A selection added to that selection, whichever it is.
            extraModuleImports ? null,
          }@settings:
          configuration settings;
        # The same arguments and `ecosystemArgs`, the evaluator's
        # arguments merged over the composed call last.
        mkConfigurationWithEcosystemArgs =
          {
            modules ? [ ],
            specialArgs ? null,
            cacheableOutputs ? { },
            defaultPkgs ? null,
            ecosystemSrc ? null,
            moduleImports ? null,
            extraModuleImports ? null,
            ecosystemArgs ? null,
          }@settings:
          configuration settings;
      };
    in
    {
      caisson = (prev.caisson or { }) // {
        nixops4 = integration.namespace;
      };
    };

}
