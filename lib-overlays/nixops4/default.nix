# SPDX-License-Identifier: MIT
#
# The nixops4 integration, the upstream-compatible one: it takes the
# modules of a root component as NixOps4 users write them for NixOps4's
# `mkRoot`, of NixOps4's class `nixops4Component`, and caisson evaluates
# every component of the deployment. The native integrations,
# caisson-nixops4 and its composite and resource, take caisson's form
# instead.
#
# A nixops4 configuration, named `nixops4` for the output it fills,
# declares the root composite beneath it under the name `root` from
# those modules, and publishes the root as the caisson-nixops4
# configuration does. Every component is evaluated with NixOps4's
# class name, so a module that sets `_class = "nixops4Component"`
# loads, and with NixOps4's resource, type and providers options.
#
# Upstream declares `members` and the resource options on every
# component and decides which kind a component is when its export is
# read: a component whose `resourceType` is defined is a resource. A
# composite here collects the definitions of each member under
# `members.<name>` and decides the same way, with a probe evaluation
# of the member's modules over NixOps4's own base modules. A member
# becomes a caisson-nixops4-resource or a caisson-nixops4-composite
# configuration declared beneath the composite, evaluated with the
# same modules. A member that sets `type` and also has members is
# refused; upstream drops the members.
#
# The `members` module argument is the one upstream gives: in a
# composite, the configs of its members, which a composite reads to
# wire one member to another (`members.db.outputs.address`); in a
# resource, nothing. A composite reads its members' configs through its
# full evaluation, so every composite sets `unsafeCrossChildReferences`
# for the class of its members.
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
    ((mkLibOverlay ../caisson-nixops4) // { key = "caisson-nixops4"; })
    ((mkLibOverlay ../caisson-nixops4-composite) // { key = "caisson-nixops4-composite"; })
    ((mkLibOverlay ../caisson-nixops4-resource) // { key = "caisson-nixops4-resource"; })
  ];

  overlay =
    final: prev:
    let
      native = final.caisson.caisson-nixops4;
      composites = final.caisson.caisson-nixops4-composite;
      resources = final.caisson.caisson-nixops4-resource;
      context = "lib.caisson.nixops4";
      upstreamClass = "nixops4Component";

      # The options every upstream component has beside `members`:
      # NixOps4's resource, type and providers options.
      componentBase = src: [
        (native.componentModule src "resource")
        (native.componentModule src "provider-values")
        (native.componentModule src "provider-declarations")
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
            ${context}: the member ${composites.showPath (path ++ [ name ])} sets `type`, which makes it a
            resource, and declares members, which a resource does not hold.
            NixOps4 would drop them; declare them in a composite instead.
          ''
        else if isResource then
          "caisson-nixops4-resource"
        else
          "caisson-nixops4-composite";

      # The module of an upstream composite that turns `members.<name>`
      # into the configurations declared beneath it.
      membersModule =
        ctx:
        { src, deploy }:
        final.caisson.integrations.caissonModule {
          key = "caisson.nixops4.members";
          file = "caisson-nixops4:members";
          module =
            { config, lib, ... }:
            let
              kinds = builtins.mapAttrs (kindOf {
                inherit lib src;
                inherit (deploy) path;
                specialArgs = ctx.specialArgs // {
                  inherit lib;
                  inherit (deploy) resourceProviderSystem;
                };
              }) config.members;
              ofKind = kind: lib.filterAttrs (name: _: kinds.${name} == kind) config.members;
            in
            {
              options.members = lib.mkOption {
                type = lib.types.lazyAttrsOf lib.types.deferredModule;
                default = { };
                description = ''
                  The member components, by name, as NixOps4 declares them: a
                  member that sets `type` is a resource, any other a composite.
                '';
              };
              # A composite reads its members' configs, through its full
              # evaluation.
              config.caisson.forDirectChildren.unsafeCrossChildReferences.${upstreamClass} = true;
              config.caisson.caisson-nixops4-composite.configurations = builtins.mapAttrs (
                _: module: compositeOf ctx [ module ]
              ) (ofKind "caisson-nixops4-composite");
              config.caisson.caisson-nixops4-resource.configurations = builtins.mapAttrs (
                _: module: resourceOf ctx [ module ]
              ) (ofKind "caisson-nixops4-resource");
            };
        };

      # The outputs of the resource at `path` that a tool may cache, from
      # the allow-list of the nixops4 configuration.
      cacheableModule =
        ctx: deploy:
        final.caisson.integrations.caissonModule {
          key = "caisson.nixops4.cacheableOutputs";
          file = "caisson-nixops4:cacheableOutputs";
          module =
            { lib, ... }:
            {
              options.cacheableOutputs = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = ctx.cacheableOutputs.${builtins.concatStringsSep "." deploy.path} or [ ];
                readOnly = true;
                description = ''
                  The outputs of this resource a tool may cache, from
                  `cacheableOutputs` of the nixops4 configuration.
                '';
              };
            };
        };

      # The arguments the native constructors receive for a component
      # with `modules`.
      componentArgs = ctx: modules: {
        configModule = modulesModule modules;
        inherit (ctx) ecosystemSrc;
        specialArgs = ctx.specialArgs;
      };

      # An upstream composite: NixOps4's class and options, `members`
      # collected and declared beneath as configurations, and the
      # configs of the members as its `members` argument. A member's
      # own `members` argument holds the members it declares itself.
      compositeOf =
        ctx: modules:
        composites.compositeWith {
          class = upstreamClass;
          baseModules =
            { src, deploy }:
            componentBase src
            ++ [
              (membersModule ctx { inherit src deploy; })
            ];
          membersArg = { finalized, ... }: builtins.mapAttrs (_: member: member.value.config) finalized;
          memberArgs = deploy: name: native.memberArgs deploy name // { members = { }; };
        } (componentArgs ctx modules);

      # An upstream resource: NixOps4's class and options, and the
      # outputs the configuration allows a tool to cache.
      resourceOf =
        ctx: modules:
        resources.resourceWith {
          class = upstreamClass;
          baseModules = { src, deploy }: componentBase src ++ [ (cacheableModule ctx deploy) ];
        } (componentArgs ctx modules);

      # The evaluator's call, on the lib of the view being evaluated:
      # the framework modules of the class, the selection, the
      # configuration's module and the root composite made from
      # `modules`, with the composition's pinned sources as the `inputs`
      # special argument. `ecosystemArgs`, which only the twin's pattern
      # admits, is merged over the call last.
      evaluate =
        args:
        { lib, manifest }:
        let
          selection = lib.caisson.integrations;
          registry = lib.caisson.modules.nixops4 or { };
          frameworkModules = selection.frameworkModules "nixops4" registry;
          moduleImports = selection.moduleImportsOf "nixops4" { inherit lib manifest; } args;
          ctx = {
            ecosystemSrc = args.ecosystemSrc or null;
            specialArgs = {
              inputs = manifest.sources;
            }
            // (if (args.specialArgs or null) != null then args.specialArgs else { });
            cacheableOutputs = args.cacheableOutputs or { };
          };
          rootModule = selection.caissonModule {
            key = "caisson.nixops4.root";
            file = "caisson-nixops4:root";
            module = {
              caisson.caisson-nixops4-composite.configurations.root = compositeOf ctx (args.modules or [ ]);
            };
          };
          moduleList = frameworkModules ++ moduleImports registry ++ [ rootModule ];
          evaluated = lib.evalModules (
            {
              class = "nixops4";
              specialArgs = {
                inherit lib;
                inputs = manifest.sources;
              };
              modules = moduleList;
            }
            // (if (args.ecosystemArgs or null) != null then args.ecosystemArgs else { })
          );
        in
        {
          value = evaluated;
          ecosystems.nixops4 = native.ecosystemAccountOf {
            explicit = args.ecosystemSrc or null;
            inherit manifest;
          };
          modules = moduleList;
          outputs.root = native.rootOf {
            inherit manifest;
            root = evaluated.config.caisson.caisson-nixops4-composite.configurations.root;
          };
        };

      configuration =
        args:
        final.caisson.integrations.mkModuleConfiguration {
          selection = {
            class = "nixops4";
            inherit args;
          };
          type = "nixops4";
          defaultPkgs = args.defaultPkgs or null;
          inherit (native) exportsTo;
          evaluate = evaluate args;
        };

      integration = final.caisson.integrations.mkIntegration {
        name = "nixops4";
        class = "nixops4";
        # What these return is a configuration, a function of
        # `{ name, parent }`: the parent that declares it under
        # `caisson.nixops4.configurations.<name>` finalizes it.
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
            # The selection over the nixops4 class of the registry,
            # replacing the default of the class.
            moduleImports ? null,
            # A selection added to that selection, whichever it is.
            extraModuleImports ? null,
          }@args:
          configuration args;
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
          }@args:
          configuration args;
      };
    in
    {
      caisson = (prev.caisson or { }) // {
        nixops4 = integration.namespace;
      };
    };

}
