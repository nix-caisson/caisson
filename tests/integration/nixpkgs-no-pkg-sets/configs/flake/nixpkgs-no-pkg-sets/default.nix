# SPDX-License-Identifier: MIT
# A consumer that gets the nixpkgs machinery through the registry but
# declares no package sets: `pkgs` stays flake-parts' own default and
# the `pkgSets` argument is empty. The composition declares no
# namespace either, so this also covers the nixpkgs flake module
# reaching a composition that names no package scope: with nothing
# selecting one, the name is never needed.
{ ... }:
{ ... }:
{
  systems = [ "x86_64-linux" ];

  perSystem =
    { pkgs, pkgSets, ... }:
    {
      checks.nixpkgs-no-pkg-sets-success =
        assert pkgSets == { };
        assert pkgs ? runCommand;
        pkgs.runCommand "nixpkgs-no-pkg-sets-success" { } "touch $out";
    };
}
