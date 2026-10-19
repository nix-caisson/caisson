# SPDX-License-Identifier: MIT
#
# The kubenix integration: it owns the `kubenix` class, the class of
# kubenix's modules. A kubenix configuration is a set of Kubernetes
# resources written as kubenix modules, which import the kubenix modules
# they use from the `kubenix` argument (`kubenix.modules.k8s`). It is
# evaluated per system, once for each system in force where it is declared, on the
# package set selected for it.
#
# kubenix evaluates its modules with its `evalModules`: `evalModules` on
# the library of the package set extended with kubenix's
# `upstreamables.nix`, with the special argument `kubenix` holding its
# library, its `evalModules` and its modules. caisson makes that
# evaluation on the composed library extended the same way.
#
# The output is `result`, the resources as a JSON file, which
# `kubectl apply -f` reads; it is the `kubernetes.result` of kubenix's
# `k8s` module, so a configuration that imports that module has it. A
# configuration is published as `kubenixConfigurations.<system>.<name>`,
# the evaluation, whose `config.kubernetes.result` is the result.
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
      context = "lib.caisson.kubenix.mkConfiguration";

      resolveEcosystemSrc = final.caisson.integrations.resolveEcosystemSrc {
        name = "kubenix";
        context = "caisson.kubenix";
      };

      # A kubenix source: the kubenix flake or source tree, which holds
      # its library at `lib` and its modules at `modules`.
      assertKubenixSrc =
        ecosystemSrc:
        let
          path = if builtins.isAttrs ecosystemSrc then ecosystemSrc.outPath or null else ecosystemSrc;
        in
        if
          path != null
          && builtins.pathExists "${path}/lib/upstreamables.nix"
          && builtins.pathExists "${path}/lib/eval-modules.nix"
          && builtins.pathExists "${path}/modules/default.nix"
        then
          ecosystemSrc
        else
          throw "${context} requires `ecosystemSrc` to be a kubenix flake or source tree (holding lib/upstreamables.nix, lib/eval-modules.nix and modules).";

      evaluate =
        args:
        { lib, manifest }:
        let
          selection = lib.caisson.integrations;
          src = assertKubenixSrc (resolveEcosystemSrc {
            explicit = args.ecosystemSrc or null;
            manifest = lib.caisson-core.libManifest or { };
          });

          name = manifest.name or null;
          inherit (manifest) system;
          what =
            if name != null then
              "the kubenix configuration `${name}` for ${system}"
            else
              "this kubenix configuration for ${system}";

          pkgSets = selection.pkgSetsForSystem { inherit context what; } manifest system;
          pkgs = selection.pkgSetOf { inherit context what; } manifest pkgSets;

          # The composed library extended with kubenix's
          # `upstreamables.nix`, as kubenix extends the library of the
          # package set. `extend` extends the library of nixpkgs, so the
          # composed library is laid over it again, with the module
          # system of the extension.
          kubenixLib = lib.extend (
            self: super:
            lib
            // {
              inherit (super) modules types evalModules;
            }
            // import "${src}/lib/upstreamables.nix" {
              lib = self;
              inherit pkgs;
            }
          );

          registry = lib.caisson.modules.kubenix or { };
          frameworkModules = selection.frameworkModules "kubenix" registry;
          moduleImports = selection.moduleImportsOf "kubenix" { inherit lib manifest; } args;

          # The configuration's module: the module passed, else the
          # configuration registered under the configuration's name
          # (`configs/kubenix/<name>`), else none.
          registered = lib.caisson.configs.kubenix or { };
          configModule =
            if (args.configModule or null) != null then
              args.configModule
            else if name != null then
              registered.${name} or null
            else
              null;

          value = kubenixLib.evalModules (
            {
              class = "kubenix";
              specialArgs = {
                inherit pkgs pkgSets;
                lib = kubenixLib;
                kubenix = {
                  lib = import "${src}/lib" {
                    inherit pkgs;
                    inherit (pkgs) lib;
                  };
                  evalModules = import "${src}/lib/eval-modules.nix" { inherit pkgs; };
                  modules = import "${src}/modules";
                };
              }
              // (if (args.specialArgs or null) != null then args.specialArgs else { });
              modules =
                frameworkModules
                ++ moduleImports registry
                ++ (if configModule == null then [ ] else [ configModule ])
                ++ [
                  {
                    _file = "caisson-kubenix:args";
                    config._module.args = {
                      inherit pkgs;
                      name = "default";
                    };
                  }
                ];
            }
            // (if (args.ecosystemArgs or null) != null then args.ecosystemArgs else { })
          );
        in
        {
          inherit value;
          outputs.result =
            value.config.kubernetes.result
              or (throw "${what} has no `kubernetes.result`; it imports kubenix's `k8s` module from `kubenix.modules.k8s` to have one.");
        };

      # A kubenix configuration is published as
      # `kubenixConfigurations.<system>.<name>`, the evaluation kubenix's
      # `evalModules` returns, whose `config.kubernetes.result` is its
      # result.
      exportsTo = {
        attrset = "kubenixConfigurations";
        bySystem = true;
        value = manifest: manifest.value;
      };

      configuration =
        args:
        final.caisson.integrations.mkModuleConfiguration {
          type = "kubenix";
          # A kubenix configuration is evaluated per system: it has an
          # evaluation for every system in force where it is declared.
          perSystem = true;
          defaultPkgs = args.defaultPkgs or null;
          inherit exportsTo;
          evaluate = evaluate args;
        };

      integration = final.caisson.integrations.mkIntegration {
        name = "kubenix";
        class = "kubenix";
        # A kubenix configuration that is a top, as a tool reads it: the
        # evaluation, or the evaluations by system where several are in
        # force.
        top = final.caisson.integrations.topValue;
        # What these return is a configuration, a function of
        # `{ name, parent }`: a parent that declares it under
        # `caisson.kubenix.configurations.<name>` finalizes it, and
        # `mkTopConfiguration` finalizes it at a top.
        mkConfiguration =
          {
            # The configuration's module. When absent, the configuration
            # registered under the configuration's name
            # (`lib.caisson.configs.kubenix.<name>`), if any. Further
            # modules of the class are selected with `moduleImports`,
            # from the registry.
            configModule ? null,
            # The kubenix flake or source tree; resolved from the
            # composition's declarations when absent.
            ecosystemSrc ? null,
            # The package set the configuration runs on: a function
            # that receives the package sets available where it is
            # declared, by package config name, each for the system of
            # the evaluation, and returns the set to run on. When
            # absent, the selection of the nearest configuration above,
            # and the set named `default` where none above selects.
            defaultPkgs ? null,
            # The selection over the kubenix class of the registry. It
            # replaces the default of the class, which is every entry
            # named `default` followed by what the configurations
            # above added.
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
            defaultPkgs ? null,
            moduleImports ? null,
            extraModuleImports ? null,
            specialArgs ? null,
            ecosystemArgs ? null,
          }@args:
          configuration args;
      };
    in
    {
      caisson = (prev.caisson or { }) // {
        kubenix = integration.namespace;
      };
    };

}
