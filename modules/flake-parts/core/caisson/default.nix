# SPDX-License-Identifier: MIT
args@{
  libOverlays,
  modules,
}:
{ mkModule, ... }:
{ config, lib, ... }:
{
  imports = [
    (mkModule (lib.caisson.importApply ./modules.nix args))
    (mkModule (lib.caisson.importApply ./libOverlays.nix args))
  ];
}
