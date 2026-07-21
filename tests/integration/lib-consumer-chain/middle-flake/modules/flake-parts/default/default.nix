# SPDX-License-Identifier: MIT
{ ... }:
{ lib, ... }:
{
  options.middleChain.moduleLoaded = lib.mkOption {
    type = lib.types.bool;
    description = "Whether the middle-chain flake module was imported.";
    default = true;
  };
}
