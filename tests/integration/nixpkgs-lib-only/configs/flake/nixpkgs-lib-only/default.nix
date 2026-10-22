# SPDX-License-Identifier: MIT
#
# Builds a package set on a library whose source holds only nixpkgs'
# `lib` directory. nixpkgs checks the maintainers of every derivation
# it creates, so the set evaluates only if its lib carries the
# `maintainers` and `teams` of the package set's source. The set's lib
# also carries the `licenses` and `sourceTypes` of that source.
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
    in
    {
      checks.nixpkgs-lib-only =
        assert pkgs.hello.drvPath == upstream.hello.drvPath;
        assert pkgs.lib.maintainers == upstream.lib.maintainers;
        assert builtins.attrNames pkgs.lib.teams == builtins.attrNames upstream.lib.teams;
        assert pkgs.lib.licenses == upstream.lib.licenses;
        assert pkgs.lib.sourceTypes == upstream.lib.sourceTypes;
        pkgs.runCommand "nixpkgs-lib-only" { } "touch $out";
    };
}
