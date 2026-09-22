# SPDX-License-Identifier: MIT
#
# The nixos integration: it owns the `nixos` class and
# evaluates it with `nixos/lib/eval-config.nix` from a nixpkgs source
# tree. `compose` (in compose.nix) is the composition of the class,
# shared with any integration that evaluates the class another way.
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
            system =
              args.system or (common.checkedPkgSets.pkgs.stdenv.hostPlatform.system
                or (common.checkedPkgSets.pkgs.system or null)
              );
          };
        };
      evalConfig = composed: callArgs: import "${composed.src}/nixos/lib/eval-config.nix" callArgs;

      # eval-config with nixpkgs' module list passed explicitly as
      # `baseModules`.
      mkConfigurationFull =
        rawArgs:
        let
          args = final.caisson.integrations.checkArgs {
            context = "lib.caisson.nixos.mkConfigurationFull";
            accepted = [
              "ecosystemSrc"
              "pkgSets"
              "configModule"
              "moduleImports"
              "specialArgs"
              "system"
            ];
            inherit hints;
            open = "lib.caisson.nixos.mkConfigurationWithEcosystemArgs";
          } rawArgs;
          composed = composeEvalConfig args;
        in
        evalConfig composed (
          composed.ecosystemArgs
          // {
            baseModules = import "${composed.src}/nixos/modules/module-list.nix";
          }
        );

      hints = {
        pkgs = "pass the package set as `pkgSets.pkgs`.";
        baseModules = "the base module list belongs to the entry point: mkConfiguration and mkConfigurationFull evaluate with NixOS' module list, lib.caisson.nixos-minimal.mkConfiguration without it.";
      };
      integration = final.caisson.integrations.mkIntegration {
        name = "nixos";
        class = "nixos";
        accepted = [ "system" ];
        inherit hints;
        compose = composeEvalConfig;
        evaluate = evalConfig;
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
