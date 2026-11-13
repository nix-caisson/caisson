# SPDX-License-Identifier: MIT
#
# The checks tests/volatile-checks/check.sh builds: `passing` and
# `failing`, the derivations `lib.caisson.mkVolatileCheck` returns for a
# program that exits with status 0 and for a program that exits with
# status 1. `nonce` is part of the name of each program, so each run of
# the script builds markers no store holds yet.
#
# caisson is the flake of this checkout, and nixpkgs is the pin of
# tests/dependencies. The script evaluates this file with `--impure`,
# since it reads both flakes with `builtins.getFlake` by path.
{ nonce }:
let
  caisson = builtins.getFlake (toString ../..);
  nixpkgs = (builtins.getFlake (toString ../dependencies)).inputs.nixpkgs;
  pkgs = nixpkgs.legacyPackages.${builtins.currentSystem};
  check =
    name: status:
    caisson.lib.caisson.mkVolatileCheck {
      inherit pkgs;
      name = "volatile-checks-${name}";
      program = pkgs.writeShellScript "volatile-checks-${name}-${nonce}" ''
        echo "the program of the check ${name} exits with status ${status}"
        exit ${status}
      '';
    };
in
{
  passing = check "passing" "0";
  failing = check "failing" "1";
}
