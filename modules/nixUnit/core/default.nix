# SPDX-License-Identifier: MIT
#
# The core module of the `nixUnit` class, forced into every nix-unit
# configuration: the options of caisson and the checks at the top
# level of its options (the `generic` registry entries `caisson` and
# `top-level-checks`, reached through the closure), and the options of
# a nix-unit configuration. `tests` is the file nix-unit reads and
# `package` is the nix-unit program that reads it. The nix-unit
# integration builds the check `unit` from both (lib-overlays/nix-unit).
{ closure-lib, ... }:
{ lib, pkgs, ... }:
{
  imports = [
    closure-lib.caisson.modules.generic.caisson
    closure-lib.caisson.modules.generic.top-level-checks
  ];

  options.tests = lib.mkOption {
    type = lib.types.path;
    example = lib.literalExpression "./tests/unit";
    description = ''
      The file nix-unit reads, or a directory whose `default.nix` is
      that file. The file is a function that returns nix-unit's suite,
      an attribute set of test cases whose names begin with `test`, each
      an `expr` and its `expected` value. The function receives `lib`,
      the library a module of the configuration that declares this
      nix-unit configuration receives, `manifest`, the manifest of that
      library, and `dependencies`, the pinned dependencies of this
      nix-unit configuration by name.

      nix-unit evaluates the file inside the build sandbox, where Nix can
      fetch nothing. The check builds the library again there from the
      record of the library and from the store paths of its
      dependencies, so the file must lie in the Nix store, as every file
      of a flake does.
    '';
  };

  options.package = lib.mkOption {
    type = lib.types.package;
    default = pkgs.nix-unit;
    defaultText = lib.literalExpression "pkgs.nix-unit";
    description = ''
      The nix-unit program the check runs: by default the package
      `nix-unit` of the package set the configuration runs on.
    '';
  };
}
