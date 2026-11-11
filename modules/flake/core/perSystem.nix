# SPDX-License-Identifier: MIT
#
# The checks of a flake, for each system of its `systems`: the
# entries of flake-parts' `checks`, and `caisson.checks` beside them.
# A third-party flake-parts module defines its checks in `checks`, as
# treefmt-nix defines `checks.treefmt`. An entry of `caisson.checks`
# without a `derivation` annotates the entry of `checks` of the same
# name, and an entry with a `derivation` declares a check, which is
# defined in `checks` as well, so `nix flake check` builds it. The
# flake-parts integration records the declarations of each system in
# the `checks` of the manifest of the flake.
{ lib, ... }:
{
  perSystem =
    {
      config,
      options,
      system,
      pkgs,
      ...
    }:
    let
      integrations = lib.caisson.integrations;

      # The package set of every package config of the flake that builds
      # one for this system, by the name of the package config.
      pkgSets = builtins.mapAttrs (_: packageConfig: packageConfig.children.nixpkgs.${system}.value) (
        lib.filterAttrs (_: packageConfig: packageConfig.children.nixpkgs ? ${system}) (
          lib.caisson-core.evalManifest.pkgSets or { }
        )
      );

      # The derivation of each entry of `caisson.checks` that sets one,
      # for the `pkgs` of `perSystem` for this system.
      built = builtins.mapAttrs (_: entry: entry.derivation { inherit pkgs pkgSets; }) (
        lib.filterAttrs (_: entry: entry.derivation != null) config.caisson.checks
      );

      # The declarations as the integration takes them: a `derivation`
      # is a function of `{ pkgs, pkgSets }`, which here returns the
      # derivation built for this system.
      declared =
        builtins.mapAttrs
          (
            name: declaration:
            declaration
            // {
              derivation = if built ? ${name} then _: built.${name} else null;
            }
          )
          (
            integrations.checkDeclarationsOf {
              option = options.caisson.checks;
              value = config.caisson.checks;
            }
          );

      # The entries of `checks` that no entry of `caisson.checks` with
      # a `derivation` defines: the checks other modules define.
      plainNames = builtins.filter (name: !(built ? ${name})) (builtins.attrNames config.checks);
      plain = lib.genAttrs plainNames (name: {
        derivation = _: config.checks.${name};
        category = "build";
        description = null;
        enable = true;
        code = integrations.definitionCodeOf options.checks name;
      });

      # An entry of `caisson.checks` without a `derivation` annotates
      # the entry of `checks` of the same name. An annotation of a name
      # `checks` does not hold keeps a null `derivation`: the
      # integration refuses it unless it declares a default check of
      # that name.
      annotated =
        name: declaration:
        if declaration.derivation != null || !(plain ? ${name}) then
          declaration
        else
          plain.${name}
          // {
            category = if declaration.category != null then declaration.category else "build";
            inherit (declaration) description enable;
            code = plain.${name}.code ++ declaration.code;
          };
    in
    {
      options.caisson.checks = lib.mkOption {
        type = lib.types.attrsOf lib.caisson-core.types.check;
        default = { };
        example = lib.literalExpression ''
          {
            treefmt.category = "format";
            debug-disabled = {
              derivation = { pkgs, ... }: pkgs.runCommand "debug-disabled" { } "touch $out";
              category = "eval";
              description = "the debug output is not published";
            };
          }
        '';
        description = ''
          The checks of the flake for this system, by name. An entry with
          a `derivation` declares a check: it names its `category`, and
          caisson calls its `derivation` with the `pkgs` of `perSystem`
          and the package sets for this system, and defines the
          derivation it returns in `checks` under the same name. An entry
          without a `derivation` annotates the entry of `checks` of
          the same name, which another module defines: it gives the check
          a `category` and a `description`, or turns it off with
          `enable = false`. An entry of `checks` that no entry here
          annotates is a check of the category `build`.
        '';
      };

      options.caisson.checkDeclarations = lib.mkOption {
        type = lib.types.raw;
        internal = true;
        readOnly = true;
        description = ''
          The checks of the flake for this system, by name, as the
          flake-parts integration records them: the entries of `checks`
          and of `caisson.checks`, each with its `derivation`, a function
          of `{ pkgs, pkgSets }` that returns the derivation built here, `category`,
          `description`, `enable` and `code`, the positions of the
          definitions that declare it.
        '';
      };

      config = {
        checks = lib.filterAttrs (name: _: config.caisson.checks.${name}.enable) built;
        caisson.checkDeclarations = plain // builtins.mapAttrs annotated declared;
      };
    };
}
