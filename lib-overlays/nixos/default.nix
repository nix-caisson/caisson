# SPDX-License-Identifier: MIT
#
# The nixos integration: it owns the `nixos` class and
# evaluates it with `nixos/lib/eval-config.nix` from a nixpkgs source
# tree, over the composed library. `compose` (in compose.nix) is the
# composition of the class, shared with any integration that evaluates
# the class another way.
{
  contributeClasses,
  entries,
  mkLibOverlay,
  ...
}:
{

  imports = [
    entries.nixpkgs-lib
    # What an integration is written from, imported by key so it is
    # composed wherever this integration is.
    ((mkLibOverlay ../integrations) // { key = "integrations"; })
  ];

  overlay =
    final: prev:
    let
      resolveEcosystemSrc = final.caisson.integrations.resolveEcosystemSrc {
        name = "nixpkgs";
        context = "caisson.nixos";
      };

      composeNixos = import ./compose.nix { inherit final; };

      # The composition of the class: the module list, the special
      # arguments and the resolved nixpkgs source, from the caisson
      # arguments. Every entry point here builds on it, and so does an
      # integration that evaluates the nixos class with another
      # evaluator (nixos-minimal), through `lib.caisson.nixos.compose`.
      compose =
        {
          context ? "lib.caisson.nixos.mkConfiguration",
          # Whether the evaluation carries NixOS' nixpkgs module, so
          # the package set lands on `nixpkgs.pkgs`; without it, the
          # set is the `pkgs` module argument.
          nixpkgsModule ? true,
        }:
        args:
        composeNixos { inherit context nixpkgsModule; } args
        // {
          src = resolveEcosystemSrc {
            explicit = args.ecosystemSrc or null;
            manifest = final.caisson-core.libManifest or { };
          };
        };

      # eval-config evaluations. `system` defaults to the package set's
      # host platform.
      composeEvalConfig =
        args:
        let
          common = compose { } args;
        in
        common
        // {
          ecosystemArgs = {
            modules = common.modules;
            specialArgs = common.specialArgs;
            # `nixos/lib/eval-config.nix` of the nixpkgs source
            # defaults `lib` to `import ../../lib`, the library of the
            # tree it lives in. Naming it makes the composed library
            # what the evaluation runs on: its `evalModules`, its
            # merging and its type checking, and the library the
            # result publishes as `.lib`.
            lib = common.lib;
            system =
              args.system or (common.checkedPkgSets.pkgs.stdenv.hostPlatform.system
                or (common.checkedPkgSets.pkgs.system or null)
              );
          };
        };
      evalConfig = composed: callArgs: import "${composed.src}/nixos/lib/eval-config.nix" callArgs;

      evaluation = final.caisson.integrations.mkEvaluation {
        compose = composeEvalConfig;
        evaluate = evalConfig;
      };

      # eval-config with nixpkgs' module list passed explicitly as
      # `baseModules`. The signature is the one of `mkConfiguration`.
      mkConfigurationFull =
        {
          configModule,
          pkgSets,
          ecosystemSrc ? null,
          moduleImports ? null,
          specialArgs ? null,
          system ? null,
        }@args:
        let
          composed = composeEvalConfig args;
        in
        evalConfig composed (
          composed.ecosystemArgs
          // {
            baseModules = import "${composed.src}/nixos/modules/module-list.nix";
          }
        );

      integration = final.caisson.integrations.mkIntegration {
        name = "nixos";
        class = "nixos";
        # The signature of the entry points over the nixos class; the
        # colmena node constructors take the same arguments, and
        # `lib.caisson.nixos-minimal` these plus `prefix`. The
        # composition (compose.nix) destructures `pkgSets` and
        # `configModule` without a default and supplies the value of
        # every optional argument left out; it checks the package set
        # again, for the narrower mistake, a `pkgSets` that carries no
        # `pkgs`.
        mkConfiguration =
          {
            # The configuration's module. Further modules of the class
            # are selected with `moduleImports`, from the registry. The
            # base module list belongs to the entry point:
            # mkConfiguration and mkConfigurationFull evaluate with
            # NixOS' module list, lib.caisson.nixos-minimal.mkConfiguration
            # without it.
            configModule,
            # The package sets; `pkgSets.pkgs` is the set the evaluation
            # runs on.
            pkgSets,
            # The nixpkgs source tree; resolved from the composition's
            # declarations when absent.
            ecosystemSrc ? null,
            # The selection over the nixos class of the registry; every
            # entry named `default` when absent.
            moduleImports ? null,
            # Extra module arguments, merged over the ones the framework
            # supplies.
            specialArgs ? null,
            # eval-config's `system`; the host platform of
            # `pkgSets.pkgs` when absent.
            system ? null,
          }@args:
          evaluation args;
        # The same arguments and `ecosystemArgs`, the evaluator's
        # arguments merged over the composed call last.
        mkConfigurationWithEcosystemArgs =
          {
            configModule,
            pkgSets,
            ecosystemSrc ? null,
            moduleImports ? null,
            specialArgs ? null,
            system ? null,
            ecosystemArgs ? null,
          }@args:
          evaluation args;
        extra = {
          inherit mkConfigurationFull;
          # The two-stage composition an alt over this class reads.
          inherit compose;
        };
      };
    in
    contributeClasses prev integration.classes
    // {
      caisson = (prev.caisson or { }) // {
        nixos = integration.namespace;
      };
    };

}
