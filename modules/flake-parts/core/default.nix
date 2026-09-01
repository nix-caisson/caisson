# SPDX-License-Identifier: MIT
#
# The core flake-parts module, wired into every mkFlake evaluation by
# the flake-parts integration. Plain modules on purpose: everything
# they need comes through `lib` (the composed library in specialArgs),
# so they are imported directly rather than through mkModule.
{ ... }:
{
  imports = [ ./caisson ];
}
