# SPDX-License-Identifier: MIT
#
# The caisson-nixops4-resource integration: a resource of a NixOps4
# deployment, one real thing a provider creates, updates and deletes.
# A resource is a member of a caisson-nixops4-composite configuration,
# declared beneath it, and a deferred configuration like the composite:
# the composite finalizes it with the resource's outputs, as NixOps4
# passes them, the composite's view of its members and the deploying
# system.
#
# A resource is evaluated with NixOps4's own resource options
# (`nix/component/resource.nix`), its `type` option and its
# `providers` option. `type` is a resource type of a provider, which
# the composite usually writes from its `providers`. The resource
# reads its own outputs as `config.outputs`, and the outputs of the
# other members of its composite through the `members` module
# argument. It holds no NixOps4 members: `members` is not an option
# here, and setting it is refused where it is set.
#
# A resource may hold caisson configurations beneath it, such as a
# NixOS configuration with its home-manager configurations. NixOps4
# does not see them. A module of the class turns them into the
# resource's inputs: the NixOS adapter, registered as `nixos` in the
# class and selected by its default module, deploys the NixOS
# configuration declared beneath a resource.
#
# The resource declares which of its outputs a tool that evaluates the
# deployment ahead of time may keep in a cache (`cacheableOutputs`);
# NixOps4 marks no output as secret, so none is cacheable unless
# listed.
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
      resourceType = "caisson-nixops4-resource";

      # The options of the class beside the options NixOps4 declares.
      resourceOptions =
        { lib, ... }:
        {
          options.cacheableOutputs = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = ''
              The names of the outputs of this resource that a tool which
              evaluates the deployment ahead of time may keep in a cache
              only its user can read. NixOps4 marks no output as secret,
              so an output is not cacheable unless it is listed here.
            '';
          };
        };

      # What NixOps4 gives a resource when it evaluates the root: its
      # outputs, from the output values it passes, and its member path.
      # The outputs of a resource NixOps4 has not applied yet are calls
      # that abort the evaluation, recoverably, when read.
      deployModule =
        deploy:
        final.caisson.integrations.caissonModule {
          key = "caisson.${resourceType}.deploy";
          file = "caisson-${resourceType}:deploy";
          module = {
            config.outputs = _: { config = deploy.outputValues; };
            config.absoluteMemberPath = deploy.path;
            config._module.args.members = deploy.members;
          };
        };

      # A resource configuration of the module class `class`, evaluated
      # with the modules `baseModules` returns for the NixOps4 source
      # and the args. The native integration evaluates its class with
      # NixOps4's resource, provider-value and provider-declaration
      # modules; the upstream-compatible one builds on this with
      # NixOps4's class and its own modules.
      resourceWith =
        {
          class,
          type ? resourceType,
          baseModules,
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
              moduleList =
                baseModules { inherit src deploy; }
                ++ [ (deployModule deploy) ]
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
                # What NixOps4 reads of the resource.
                export.resource = evaluated.config._resourceForNixOps;
                cacheableOutputs = evaluated.config.cacheableOutputs or [ ];
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
              defaultPkgs = args.defaultPkgs or null;
              evaluate = evaluate deploy;
            };
        in
        final.caisson-core.mkDeferredConfiguration {
          inherit type class;
          # The deploying system and the resource's own outputs, which
          # its type declares.
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
              outputValues = builtins.mapAttrs (
                output: _:
                final.caisson-core.mkArg {
                  cacheable = builtins.elem output manifest.outputs.cacheableOutputs;
                  description = "An output of this resource.";
                }
              ) manifest.outputs.export.resource.outputsSkeleton;
            };
          configuration =
            {
              name,
              parent,
              args,
            }:
            configurationFor (nixops4.deployOf name args) { inherit name parent; };
        };

      configuration = resourceWith {
        class = resourceType;
        baseModules =
          { src, ... }:
          [
            (nixops4.componentModule src "resource")
            (nixops4.componentModule src "provider-values")
            (nixops4.componentModule src "provider-declarations")
            (final.caisson.integrations.caissonModule {
              key = "caisson.${resourceType}.resourceOptions";
              file = "caisson-${resourceType}:resourceOptions";
              module = resourceOptions;
            })
          ];
      };

      integration = final.caisson.integrations.mkIntegration {
        name = resourceType;
        class = resourceType;
        # What these return is a deferred configuration, a function of
        # `{ name, parent, args }`: the composite that declares it under
        # `caisson.caisson-nixops4-resource.configurations.<name>`
        # finalizes it when NixOps4 deploys.
        mkConfiguration =
          {
            # The resource's module: its `type`, `inputs`, the options
            # of the modules it selects, and the caisson configurations
            # declared beneath it. When absent, the configuration
            # registered under the configuration's name, if any.
            configModule ? null,
            # The package set the configurations beneath run on: a
            # function that receives the package sets available, by
            # package config name, and returns the set to run on.
            defaultPkgs ? null,
            # The NixOps4 flake; resolved from the composition's
            # declarations when absent.
            ecosystemSrc ? null,
            # The selection over the caisson-nixops4-resource class of
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
            defaultPkgs ? null,
            ecosystemSrc ? null,
            moduleImports ? null,
            extraModuleImports ? null,
            specialArgs ? null,
            ecosystemArgs ? null,
          }@args:
          configuration args;
        # What the upstream-compatible integration builds on.
        extra = {
          inherit resourceWith deployModule resourceOptions;
        };
      };
    in
    {
      caisson = (prev.caisson or { }) // {
        caisson-nixops4-resource = integration.namespace;
      };
    };

}
