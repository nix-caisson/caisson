# SPDX-License-Identifier: MIT
#
# A flake of the registered world, declared inside its top.
{ ... }:
{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages.default = pkgs.hello;
    };
}
