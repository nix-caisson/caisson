# SPDX-License-Identifier: MIT
#
# The flake-parts caisson top of the nix-unit test, evaluated for
# x86_64-linux and aarch64-linux. It declares the nix-unit
# configurations `passing` and `failing`, which take the modules
# registered under their names (configs/nixUnit).
{ ... }:
{ lib, ... }:
{
  systems = [
    "x86_64-linux"
    "aarch64-linux"
  ];
  caisson.nix-unit.configurations = lib.caisson.nix-unit.mkConfigurations { };
}
