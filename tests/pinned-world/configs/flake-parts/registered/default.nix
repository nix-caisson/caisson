# SPDX-License-Identifier: MIT
#
# A flake of the registered world, declared inside its caisson top.
{ ... }:
{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages.default = pkgs.hello;
    };
}
