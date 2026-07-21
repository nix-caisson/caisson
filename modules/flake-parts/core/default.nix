# SPDX-License-Identifier: MIT
mkLibArgs@{
  libOverlays,
  modules,
}:
{ mkModule, ... }:
{ config, lib, ... }:
{
  imports = [
    (mkModule (lib.caisson.importApply ./caisson mkLibArgs))
  ];
}
