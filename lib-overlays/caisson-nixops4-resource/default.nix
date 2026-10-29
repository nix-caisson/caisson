# SPDX-License-Identifier: MIT
#
# The caisson-nixops4-resource integration: a resource of a NixOps4
# deployment, one real thing a provider creates, updates and deletes.
# A resource is a member of a caisson-nixops4-composite configuration,
# declared beneath it, and a deferred configuration like the composite
# (caisson-core's `mkDeferredConfiguration`). Its args are
# `outputValues`, its outputs as NixOps4 passes them, and
# `resourceProviderSystem`, the system NixOps4 runs providers on. The
# composite finalizes it with its part of the composite's args.
#
# A resource is evaluated with NixOps4's own resource options
# (`nix/component/resource.nix`), its `type` option and its
# `providers` option. `type` is a resource type of a provider, which
# the composite usually writes from its `providers`. The resource
# reads its own outputs as `config.outputs`. It reads the outputs of
# the other members of its composite through what the composite writes
# into it, from the composite's `members` module argument. It holds no
# NixOps4 members: `members` is not an option here, and setting it is
# refused where it is set.
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
#
# The helpers the composite integration, the upstream-compatible
# integration and the NixOS adapters build on are published under
# `extra`, as `lib.caisson.caisson-nixops4-resource.<helper>`.
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
  ];

  overlay =
    final: prev:
    let
      resourceType = "caisson-nixops4-resource";
      context = "lib.caisson.${resourceType}";

      resolveEcosystemSrc = final.caisson.integrations.resolveEcosystemSrc ecosystem;
      ecosystemAccountOf = final.caisson.integrations.ecosystemAccountOf ecosystem;
      ecosystem = {
        name = "nixops4";
        context = "caisson.${resourceType}";
      };

      # NixOps4's component modules are files of its source, which the
      # composite and resource integrations evaluate in caisson's
      # evaluations; its `local` provider is a module its flake
      # publishes.
      assertNixops4EcosystemSrc =
        ecosystemSrc:
        if
          ecosystemSrc ? modules
          && ecosystemSrc.modules ? nixops4Provider
          && builtins.pathExists "${ecosystemSrc}/nix/component/resource.nix"
          && builtins.pathExists "${ecosystemSrc}/nix/component/provider-values.nix"
          && builtins.pathExists "${ecosystemSrc}/nix/component/provider-declarations.nix"
        then
          ecosystemSrc
        else
          throw "${context} requires `ecosystemSrc.modules.nixops4Provider` and NixOps4's component modules under `nix/component` (a NixOps4 flake).";

      # The NixOps4 source of a configuration: `explicit` when given,
      # else what the composition declares or pins under the name
      # `nixops4`, as recorded on `manifest`.
      ecosystemSrcOf =
        { explicit, manifest }:
        assertNixops4EcosystemSrc (resolveEcosystemSrc {
          inherit explicit manifest;
        });

      # A component module of NixOps4, by its file name under
      # `nix/component`.
      componentModule = src: name: "${src}/nix/component/${name}.nix";

      # The package set of a deploying system: the set the selection in
      # force at `manifest` returns, for that system.
      pkgsFor =
        manifest: system:
        let
          what = "the deployment for ${system}";
          pkgSets = final.caisson.integrations.pkgSetsForSystem { inherit context what; } manifest system;
        in
        final.caisson.integrations.pkgSetOf { inherit context what; } manifest pkgSets;

      # The member path of a component, as NixOps4 writes it.
      showPath = path: if path == [ ] then "the root" else builtins.concatStringsSep "." path;

      # The integrations whose configurations are composites: the
      # native composite and the root of the upstream-compatible
      # integration.
      compositeTypes = [
        "caisson-nixops4-composite"
        "nixops4"
      ];

      # The member path of the component `manifest` describes, from the
      # root, as NixOps4's `absoluteMemberPath` holds it: empty for a
      # component whose parent is not a composite, which is the root,
      # else the path of the parent, the childless manifest of the
      # composite, and the name of the component. It is built from the
      # names the components are declared under.
      absoluteMemberPathOf =
        manifest:
        if builtins.elem (manifest.parent.type or null) compositeTypes then
          manifest.parent.outputs.path ++ [ manifest.name ]
        else
          [ ];

      # The NixOS configuration a resource named `resource` deploys, from
      # the NixOS configurations declared beneath it (`declared`): the
      # only one, evaluated for one system. `context` names the module
      # that asks, for the errors.
      machineOf =
        {
          context,
          resource,
          declared,
        }:
        let
          names = builtins.attrNames declared;
          only = declared.${builtins.head names};
          evaluations = builtins.attrValues only;
        in
        if builtins.length names != 1 then
          throw ''
            ${context}: the resource `${resource}` declares the NixOS configurations
            ${builtins.concatStringsSep ", " (builtins.map (n: "`${n}`") names)}, and a resource deploys one.
            Declare each as the NixOS configuration of a resource of its own.
          ''
        else if (only._type or null) == "caisson-manifest" then
          only
        else if builtins.length evaluations == 1 then
          builtins.head evaluations
        else
          throw ''
            ${context}: the NixOS configuration `${builtins.head names}` of the resource
            `${resource}` is evaluated for ${builtins.concatStringsSep ", " (builtins.attrNames only)},
            and a resource deploys one evaluation. Declare it where a single system is in force.
          '';

      # The discovery program of a root composite for `system`, the
      # system of the tool that runs it, on the package set selected at
      # `manifest` for that system: it prints the args NixOps4 recorded.
      # It runs `nixops4 state dump` for each of `stateResources`, the
      # member paths of the resources that hold state joined with `.`,
      # in the working directory, which NixOps4 finds the flake from. It
      # passes its own arguments to NixOps4, such as `--override-input`,
      # and prints `{ outputValues, resourceProviderSystem }`. A dump
      # holds the resources that record their outputs in that state, at
      # their member paths from the root: the resources of the root
      # under `resources`, and those of a composite `a` under
      # `deployments.a`, in the same shape. Only resources with a state
      # have recorded outputs.
      discoverArgsOf =
        {
          manifest,
          src,
          stateResources,
          system,
        }:
        let
          pkgs = pkgsFor manifest system;
        in
        pkgs.writeShellApplication {
          name = "caisson-nixops4-discover";
          runtimeInputs = [
            src.packages.${system}.nixops4
            pkgs.jq
          ];
          text = ''
            merged='{}'
            states=(${final.escapeShellArgs stateResources})
            for state in "''${states[@]}"; do
              dump=$(nixops4 "$@" state dump "$state")
              merged=$(jq -cn --argjson merged "$merged" --argjson dump "$dump" '
                def outputValues:
                  ((.resources // {}) | map_values(.output_properties))
                  + ((.deployments // {}) | map_values(outputValues));
                $merged * ($dump | outputValues)
              ')
            done
            jq -cn --argjson merged "$merged" '{ outputValues: $merged, resourceProviderSystem: "${system}" }'
          '';
        };

      # The arg `resourceProviderSystem`, which every component takes.
      # A system name is no secret, so it is cacheable.
      systemArg = final.caisson-core.mkArg {
        cacheable = true;
        type = "string";
        description = "The system NixOps4 runs providers and the programs of resources on.";
      };

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

      # A resource configuration of the module class `class`, evaluated
      # with the modules `baseModules` returns for the NixOps4 source
      # and the member path, and the settings the constructor received.
      # The native integration evaluates its class with NixOps4's
      # resource, provider-value and provider-declaration modules; the
      # upstream-compatible one builds on this with NixOps4's class and
      # its own modules.
      mkResourceConfiguration =
        {
          class,
          type ? resourceType,
          baseModules,
        }:
        settings:
        let
          # The evaluator's call with the args `args`, on the lib of the
          # view being evaluated: the base modules, the outputs and the
          # member path, the framework modules of the class, the
          # selection and the configuration's module, with the
          # composition's pinned sources as the `inputs` special
          # argument and the deploying system as
          # `resourceProviderSystem`, as NixOps4 passes it.
          # `ecosystemArgs` is merged over the call last.
          evaluate =
            args:
            { lib, manifest }:
            let
              selection = lib.caisson.integrations;
              path = absoluteMemberPathOf manifest;
              src = ecosystemSrcOf {
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
              # The modules of an evaluation in which the resource's
              # outputs are `outputs`, with what NixOps4 gives a
              # resource beside them, its member path.
              modulesWith =
                outputs:
                baseModules { inherit src path; }
                ++ [
                  (selection.caissonModule {
                    key = "caisson.${type}.outputs";
                    file = "caisson-${type}:outputs";
                    module = {
                      config.outputs = _: { config = outputs; };
                      config.absoluteMemberPath = path;
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
              # The outputs are the output values NixOps4 passes. An
              # output NixOps4 has not passed fails when it is read,
              # naming itself.
              moduleList = modulesWith args.outputValues;
              evaluated = evaluationOf moduleList;
              # The evaluation that names the outputs, for `argsNeeded`.
              # Reading an output fails there with an error that names
              # the resource, since NixOps4 needs the names of the
              # outputs before it has their values.
              naming = evaluationOf (
                modulesWith (throw ''
                  ${context}: the resource at ${showPath path} reads its own outputs in its
                  `outputsSkeleton`, which names its outputs. NixOps4 needs the names of the
                  outputs of a resource before it has their values.
                '')
              );
              cacheableOutputs = evaluated.config.cacheableOutputs or [ ];
            in
            {
              value = evaluated;
              ecosystems.nixops4 = ecosystemAccountOf {
                explicit = settings.ecosystemSrc or null;
                inherit manifest;
              };
              modules = moduleList;
              outputs = {
                inherit path cacheableOutputs;
                # What NixOps4 reads of the resource.
                export.resource = evaluated.config._resourceForNixOps;
                providerConfigs = evaluated.config.providers;
              };
              # The deploying system and the resource's own outputs,
              # which its type names. An output is cacheable when the
              # resource lists it.
              argsNeeded = {
                resourceProviderSystem = systemArg;
                outputValues = builtins.mapAttrs (
                  output: _:
                  final.caisson-core.mkArg {
                    cacheable = builtins.elem output cacheableOutputs;
                    description = "An output of the resource at ${showPath path}.";
                  }
                ) naming.config.outputsSkeleton;
              };
            };
        in
        final.caisson-core.mkDeferredConfiguration {
          inherit type class;
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

      configuration = mkResourceConfiguration {
        class = resourceType;
        baseModules =
          { src, ... }:
          [
            (componentModule src "resource")
            (componentModule src "provider-values")
            (componentModule src "provider-declarations")
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
        # finalizes it with its part of the composite's args.
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
        # What the composite integration, the upstream-compatible
        # integration and the NixOS adapters build on.
        extra = {
          inherit
            mkResourceConfiguration
            resourceOptions
            ecosystemSrcOf
            componentModule
            pkgsFor
            showPath
            absoluteMemberPathOf
            machineOf
            discoverArgsOf
            systemArg
            ;
          # Where the NixOps4 source of a configuration came from, as a
          # manifest records it under `ecosystems.nixops4`.
          ecosystemAccountOf = { explicit, manifest }: ecosystemAccountOf { inherit explicit manifest; };
        };
      };
    in
    {
      caisson = (prev.caisson or { }) // {
        caisson-nixops4-resource = integration.namespace;
      };
    };

}
