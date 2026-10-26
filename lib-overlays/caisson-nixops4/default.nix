# SPDX-License-Identifier: MIT
#
# The caisson-nixops4 integration, the native NixOps4 integration's
# declaration: a configuration of the `caisson-nixops4` class, evaluated
# when the flake is, which holds the root component of a NixOps4
# deployment and publishes it as the `nixops4` output NixOps4's
# command reads.
#
# NixOps4 evaluates its root component when it deploys, again each time
# the outputs of a resource become known, and a component can read those
# outputs and compute its members from them. So the root component is a
# deferred child of the declaration (caisson-core's
# `mkDeferredConfiguration`): a `caisson-nixops4-composite`
# configuration declared under the name `root`, finalized by
# `rootFunction` with the output values NixOps4 passes. The composites
# and resources beneath it are deferred children of their composites,
# which finalize them with their part of those values. The integrations
# `caisson-nixops4-composite` and `caisson-nixops4-resource` are written
# beside this one, on the helpers it publishes under `extra`.
#
# The configuration named `nixops4`, for the output it fills, is
# published there: `_type`, `rootFunction` and `getProviders`, as
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
  ];

  overlay =
    final: prev:
    let

      resolveEcosystemSrc = final.caisson.integrations.resolveEcosystemSrc ecosystem;
      ecosystemAccountOf = final.caisson.integrations.ecosystemAccountOf ecosystem;
      ecosystem = {
        name = "nixops4";
        context = "caisson.caisson-nixops4";
      };
      context = "lib.caisson.caisson-nixops4";

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

      # What a component sees of the members of a composite, as the
      # `members` module argument: for each member, by name, its
      # `outputs`, its `members` in turn and its `absoluteMemberPath`,
      # which NixOps4's `state` option reads. It is built from the
      # output values of the composite (`outputValues`), which NixOps4
      # computes from the export of the root: by member name, a
      # resource's outputs or a composite's own output values. A
      # member's config is not reachable through it.
      membersView =
        path: outputValues:
        builtins.mapAttrs (name: values: {
          outputs = values;
          members = membersView (path ++ [ name ]) values;
          absoluteMemberPath = path ++ [ name ];
        }) outputValues;

      # The args a deferred member takes, as its composite gives them:
      # `outputValues`, the member's part of the output values;
      # `members`, the composite's view of its members (`membersView`);
      # `resourceProviderSystem`, the system NixOps4 runs providers on;
      # and `path`, the member path from the root.
      deployOf =
        what: args:
        {
          outputValues = args.outputValues or { };
          members = args.members or { };
          path = args.path or [ ];
        }
        // {
          resourceProviderSystem =
            args.resourceProviderSystem or (throw "caisson-deferred: needs ${what}.resourceProviderSystem");
        };

      # The args a composite, with args `deploy`, gives its member
      # `name`.
      memberArgs = deploy: name: {
        outputValues = deploy.outputValues.${name} or { };
        members = membersView deploy.path deploy.outputValues;
        inherit (deploy) resourceProviderSystem;
        path = deploy.path ++ [ name ];
      };

      # The args NixOps4 passes, as the declaration hands them to the
      # root composite.
      rootArgs =
        { outputValues, resourceProviderSystem }:
        {
          inherit outputValues resourceProviderSystem;
          members = { };
          path = [ ];
        };

      # The arg `resourceProviderSystem`, which every component takes.
      # A system name is no secret, so it is cacheable.
      systemArg = final.caisson-core.mkArg {
        cacheable = true;
        type = "string";
        description = "The system NixOps4 runs providers and the programs of resources on.";
      };

      # The options of the declaration's class: none of its own, so
      # only the framework's and what its modules declare.
      declarationOptions = { ... }: { };

      # The root of the deployment, as NixOps4's `mkRoot` returns it,
      # over the deferred root composite `root` of the declaration.
      # `rootFunction` finalizes it with the output values NixOps4
      # passes and returns its export. `getProviders` finalizes it with
      # no output values for `system` and builds the providers its root
      # declares, as the `getProviders` of NixOps4 does; providers
      # declared beneath the root are not collected, as upstream
      # collects none of them either.
      rootOf =
        { manifest, root }:
        {
          _type = "nixops4Component";
          rootFunction =
            {
              outputValues,
              resourceProviderSystem,
              ...
            }:
            (root.finalize {
              args = rootArgs { inherit outputValues resourceProviderSystem; };
              argsSource = "NixOps4";
            }).outputs.export;
          getProviders =
            { system }:
            let
              finalized = root.finalize {
                args = rootArgs {
                  outputValues = { };
                  resourceProviderSystem = system;
                };
                argsSource = "getProviders, with no output values";
              };
              serializable = builtins.mapAttrs (_: provider: {
                inherit (provider) executable args;
              }) finalized.outputs.providerConfigs;
            in
            (pkgsFor manifest system).writeText "nixops-root-providers" ''
              Store path contents subject to change
              ${builtins.toJSON serializable}
            '';
          # The deferred root composite, for a tool that walks the
          # deployment ahead of time.
          caisson.deferredRoot = root;
        };

      # The evaluator's call, on the lib of the view being evaluated:
      # the options of the class, the framework modules of the class, the
      # selection and the configuration's module, with the composition's
      # pinned sources as the `inputs` special argument. `ecosystemArgs`,
      # which only the twin's pattern admits, is merged over the call
      # last.
      evaluate =
        args:
        { lib, manifest }:
        let
          selection = lib.caisson.integrations;
          registry = lib.caisson.modules.caisson-nixops4 or { };
          frameworkModules = selection.frameworkModules "caisson-nixops4" registry;
          moduleImports = selection.moduleImportsOf "caisson-nixops4" { inherit lib manifest; } args;
          name = manifest.name or null;
          configModule = selection.configModuleOf {
            inherit lib name;
            class = "caisson-nixops4";
            configModule = args.configModule or null;
          };
          moduleList = [
            (selection.caissonModule {
              key = "caisson.caisson-nixops4.declarationOptions";
              file = "caisson-caisson-nixops4:declarationOptions";
              module = declarationOptions;
            })
          ]
          ++ frameworkModules
          ++ moduleImports registry
          ++ (if configModule == null then [ ] else [ configModule ]);
          evaluated = lib.evalModules (
            {
              class = "caisson-nixops4";
              specialArgs = {
                inherit lib;
                inputs = manifest.sources;
              }
              // (if (args.specialArgs or null) != null then args.specialArgs else { });
              modules = moduleList;
            }
            // (if (args.ecosystemArgs or null) != null then args.ecosystemArgs else { })
          );
          composites = evaluated.config.caisson.caisson-nixops4-composite.configurations;
          # The root composite, the composite declared under the name
          # `root`: a `nixops4` output holds one root.
          root =
            if builtins.attrNames composites == [ "root" ] then
              composites.root
            else
              throw ''
                ${context}: a nixops4 configuration holds one root composite, declared as
                `caisson.caisson-nixops4-composite.configurations.root`, and this one declares
                ${
                  if composites == { } then
                    "none"
                  else
                    builtins.concatStringsSep ", " (builtins.map (n: "`${n}`") (builtins.attrNames composites))
                }.
              '';
        in
        {
          value = evaluated;
          ecosystems.nixops4 = ecosystemAccountOf {
            explicit = args.ecosystemSrc or null;
            inherit manifest;
          };
          modules = moduleList;
          outputs.root = rootOf { inherit manifest root; };
        };

      # A nixops4 configuration is published as `nixops4`, an output that
      # holds a single value: the root of the deployment.
      exportsTo = {
        attrset = "nixops4";
        single = true;
        value = manifest: manifest.outputs.root;
      };

      configuration =
        args:
        final.caisson.integrations.mkModuleConfiguration {
          selection = {
            class = "caisson-nixops4";
            inherit args;
          };
          type = "caisson-nixops4";
          defaultPkgs = args.defaultPkgs or null;
          inherit exportsTo;
          evaluate = evaluate args;
        };

      integration = final.caisson.integrations.mkIntegration {
        name = "caisson-nixops4";
        class = "caisson-nixops4";
        # What these return is a configuration, a function of
        # `{ name, parent }`: the parent that declares it under
        # `caisson.caisson-nixops4.configurations.<name>` finalizes it.
        mkConfiguration =
          {
            # The declaration's module: the root composite, declared as
            # `caisson.caisson-nixops4-composite.configurations.root`.
            # When absent, the configuration registered under the
            # configuration's name, if any.
            configModule ? null,
            # The package set the deployment runs on: a function that
            # receives the package sets available, by package config
            # name, and returns the set to run on.
            defaultPkgs ? null,
            # The NixOps4 flake; resolved from the composition's
            # declarations when absent.
            ecosystemSrc ? null,
            # The selection over the caisson-nixops4 class of the
            # registry, replacing the default of the class.
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
        # What the composite and resource integrations build on.
        extra = {
          inherit
            exportsTo
            ecosystemSrcOf
            componentModule
            pkgsFor
            membersView
            deployOf
            memberArgs
            rootArgs
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
        caisson-nixops4 = integration.namespace;
      };
    };

}
