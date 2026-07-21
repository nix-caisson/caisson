# SPDX-License-Identifier: MIT
{ mkModule, ... }:
{ ... }:
{
  imports = [
    (mkModule ./configInfo.nix)
    (mkModule ./lib.nix)
  ];

}
