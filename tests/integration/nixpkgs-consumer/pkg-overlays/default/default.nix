# SPDX-License-Identifier: MIT
#
# The consumer's package scope, `pkgs.nixpkgs-consumer`.
{ closure-lib, ... }:
{
  overlay = closure-lib.caisson.nixpkgs.mkPackagesOverlay (callPackage: {
    integration-sample = callPackage ({ writeText }: writeText "integration-sample" "ok") { };
  }) "nixpkgs-consumer";
}
