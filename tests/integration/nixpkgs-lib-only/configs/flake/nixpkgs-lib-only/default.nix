# SPDX-License-Identifier: MIT
#
# Builds a package set on a library whose source holds only nixpkgs'
# `lib` directory. nixpkgs checks the maintainers of every derivation
# it creates, so the set evaluates only if its lib carries the
# `maintainers` and `teams` of the package set's source. The checks
# read where each function of the set's lib is defined: the
# package-set libraries and their top-level names come from the
# package set's source, and the general utilities from the library of
# the composition.
{ ... }:
{
  inputs,
  lib,
  ...
}:
{
  systems = [ "x86_64-linux" ];

  perSystem =
    { system, ... }:
    let
      pkgs = lib.caisson.nixpkgs.pkgSets.default.children.nixpkgs.${system}.value;
      upstream = import inputs.nixpkgs { inherit system; };
      fileOf = name: set: (builtins.unsafeGetAttrPos name set).file;
      # Whether the attribute `name` of `set` is defined in the library
      # of the package set's source.
      fromSet = name: set: lib.hasPrefix "${inputs.nixpkgs}/lib/" (fileOf name set);
      marked = "marked by the composition";
    in
    {
      checks.nixpkgs-lib-only =
        assert pkgs.hello.drvPath == upstream.hello.drvPath;
        assert pkgs.lib.maintainers == upstream.lib.maintainers;
        assert builtins.attrNames pkgs.lib.teams == builtins.attrNames upstream.lib.teams;
        assert pkgs.lib.licenses == upstream.lib.licenses;
        assert pkgs.lib.platforms == upstream.lib.platforms;
        assert fromSet "getExe" pkgs.lib.meta;
        assert fromSet "callPackageWith" pkgs.lib.customisation;
        assert fromSet "elaborate" pkgs.lib.systems;
        assert !(fromSet "splitString" pkgs.lib.strings);
        assert !(fromSet "evalModules" pkgs.lib.modules);
        # The test's lib overlay marks `getExe` and `splitString` in the
        # composed lib. The package set's lib takes `getExe` from the
        # package set's source and keeps the general `splitString`.
        assert lib.getExe pkgs.hello == marked;
        assert pkgs.lib.getExe pkgs.hello == upstream.lib.getExe upstream.hello;
        assert pkgs.lib.splitString "," "a,b" == [ marked ];
        pkgs.runCommand "nixpkgs-lib-only" { } "touch $out";
    };
}
