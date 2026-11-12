# SPDX-License-Identifier: MIT
#
# The system-specific part of a structural configuration, as
# flake-parts has `perSystem` for a flake: a module that is evaluated
# once for each system the children of the configuration are
# evaluated for, and whose result for each system is under
# `allSystems.<system>` (./allSystems.nix). `caisson.checks` is
# declared there, since a check is a derivation for a single system.
#
# The modules of `perSystem` take these module arguments beside
# `config`, `options` and `lib`:
#
# - `system`, the system `perSystem` is evaluated for;
# - `pkgSets`, the package set of every package config of the tree
#   that builds one for that system, by the name of the package config;
# - `pkgs`, the set of `pkgSets` that the selection of the
#   configuration picks, as `defaultPkgs` selects it.
{ lib, ... }:
let
  integrations = lib.caisson.integrations;
  manifest = lib.caisson-core.evalManifest;

  # The package set of every package config that builds one for
  # `system`, by the name of the package config.
  pkgSetsFor =
    system:
    builtins.mapAttrs (_: packageConfig: packageConfig.children.nixpkgs.${system}.value) (
      lib.filterAttrs (_: packageConfig: packageConfig.children.nixpkgs ? ${system}) (
        if manifest == null then { } else manifest.pkgSets or { }
      )
    );

  # The module arguments of `perSystem` for `system`.
  argumentsFor = system: {
    _file = "caisson-structural:perSystem";
    _module.args = rec {
      pkgSets = pkgSetsFor system;
      pkgs = integrations.pkgSetOf {
        context = "perSystem";
        what = "the structural configuration for ${system}";
      } manifest pkgSets;
    };
  };

  # The checks of the configuration for a system.
  checks =
    { config, options, ... }:
    {
      _file = "caisson-structural:perSystem";
      options.caisson.checks = lib.mkOption {
        type = lib.types.attrsOf lib.caisson-core.types.check;
        default = { };
        example = lib.literalExpression ''
          {
            evaluates = {
              derivation = pkgs.runCommand "evaluates" { } "touch $out";
              category = "eval";
              description = "the configurations inside evaluate";
            };
          }
        '';
        description = ''
          The checks of the structural configuration for this system, by
          name. An entry with a `derivation` declares a check, and it
          names its `category`. A check is gathered under
          `checks.<system>` of the outputs of the caisson top, under the
          names of the configurations from the caisson top down to this
          configuration and
          the name of the check, joined with `-`.
        '';
      };

      options.caisson.checkDeclarations = lib.mkOption {
        type = lib.types.raw;
        internal = true;
        readOnly = true;
        description = ''
          The checks of the structural configuration for this system, by
          name, as the structural integration records them, each with
          its `derivation`, `category`, `description`, `enable` and
          `code`, the positions of the definitions that declare it.
        '';
      };

      config.caisson.checkDeclarations = integrations.checkDeclarationsOf {
        option = options.caisson.checks;
        value = config.caisson.checks;
      };
    };
in
{
  options.perSystem = lib.mkOption {
    type = lib.types.deferredModule;
    default = { };
    example = lib.literalExpression ''
      { pkgs, ... }: {
        caisson.checks.evaluates = {
          derivation = pkgs.runCommand "evaluates" { } "touch $out";
          category = "eval";
        };
      }
    '';
    description = ''
      The system-specific part of the structural configuration: a module
      evaluated once for each system the children of the configuration
      are evaluated for, with `system`, `pkgs` and `pkgSets` among its
      module arguments. Its result for each system is
      `allSystems.<system>`.
    '';
    apply =
      module: system:
      (lib.evalModules {
        class = "perSystem";
        prefix = [
          "perSystem"
          system
        ];
        specialArgs = { inherit system; };
        modules = [
          module
          checks
          (argumentsFor system)
        ];
      }).config;
  };
}
