# SPDX-License-Identifier: MIT
#
# The project's package scope, `pkgs.nixpkgs-pkg-sets`, applied by the
# default overlay selection of every package config.
{ closure-lib, ... }:
{
  overlay = closure-lib.caisson.nixpkgs.mkPackagesOverlay (callPackage: {
    sample = callPackage ({ writeText }: writeText "sample" "ok") { };
  }) "nixpkgs-pkg-sets";
}
