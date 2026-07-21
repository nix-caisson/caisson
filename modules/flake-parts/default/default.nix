# SPDX-License-Identifier: MIT
{ mkModule, ... }:
{ ... }:
{
  imports = [
    (mkModule ./caisson)
  ];
}
