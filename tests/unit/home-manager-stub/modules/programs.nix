# SPDX-License-Identifier: MIT
#
# A stand-in for one file of the module tree home-manager imports
# when `minimal` is false. A minimal evaluation leaves it out, and a
# configuration that wants it imports it from `modulesPath`, the way
# the news entry announcing `minimal` describes.
{ lib, ... }:
{
  options.programs.stub.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
  };
}
