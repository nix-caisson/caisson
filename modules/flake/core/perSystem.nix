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
    { config, options, ... }:
    let
      integrations = lib.caisson.integrations;

      declared = integrations.checkDeclarationsOf {
        option = options.caisson.checks;
        value = config.caisson.checks;
      };

      # The entries of `checks` that no entry of `caisson.checks` with
      # a `derivation` defines: the checks other modules define.
      plainNames = builtins.filter (name: (declared.${name}.derivation or null) == null) (
        builtins.attrNames config.checks
      );
      plain = lib.genAttrs plainNames (name: {
        derivation = config.checks.${name};
        category = "build";
        description = null;
        enable = true;
        code = integrations.definitionCodeOf options.checks name;
        top = null;
      });

      # An entry of `caisson.checks` without a `derivation` annotates
      # the entry of `checks` of the same name. An annotation of a name
      # `checks` does not hold keeps a null `derivation`: the
      # integration refuses it unless it declares a default check of
      # that name. An entry with a `top` annotates nothing: it declares
      # the checks of a test caisson top, and an entry of `checks` of
      # the same name is refused beside it.
      annotated =
        name: declaration:
        if declaration.top != null && plain ? ${name} then
          throw ''
            caisson: `perSystem.caisson.checks.${name}`, defined at ${integrations.showCode declaration.code},
            sets a `top`, and `checks.${name}` is defined as well. An entry with a `top`
            declares the checks of a test caisson top under `${name}-`, so it annotates
            no entry of `checks`. Declare the test caisson top under another name.
          ''
        else if declaration.derivation != null || declaration.top != null || !(plain ? ${name}) then
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
              derivation = pkgs.runCommand "debug-disabled" { } "touch $out";
              category = "eval";
              description = "the debug output is not published";
            };
          }
        '';
        description = ''
          The checks of the flake for this system, by name. An entry with
          a `derivation` declares a check: it names its `category`, and
          the derivation is defined in `checks` under the same name. An
          entry without a `derivation` annotates the entry of `checks` of
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
          and of `caisson.checks`, each with its `derivation`, `category`,
          `description`, `enable` and `code`, the positions of the
          definitions that declare it.
        '';
      };

      config = {
        checks = builtins.mapAttrs (_: entry: entry.derivation) (
          lib.filterAttrs (_: entry: entry.enable && entry.derivation != null) config.caisson.checks
        );
        caisson.checkDeclarations = plain // builtins.mapAttrs annotated declared;
      };
    };
}
