# SPDX-License-Identifier: MIT
# A consumer that gets the nixpkgs machinery through the registry but
# declares no package sets: `pkgs` stays flake-parts' own default and
# the `pkgSets` argument is empty.
{ ... }:
{ ... }:
{
  systems = [ "x86_64-linux" ];

  caisson.configInfo.configName = "nixpkgs-no-pkg-sets";

  perSystem =
    { pkgs, pkgSets, ... }:
    {
      checks.nixpkgs-no-pkg-sets-success =
        assert pkgSets == { };
        assert pkgs ? runCommand;
        pkgs.runCommand "nixpkgs-no-pkg-sets-success" { } "touch $out";
    };
}
