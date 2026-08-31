# SPDX-License-Identifier: MIT
#
# The core flake-parts module, wired into every mkFlake evaluation by
# the flake-parts integration. Plain modules on purpose: everything
# they need arrives through `lib` (the composed library in
# specialArgs), so no closure application is involved.
{ ... }:
{
  imports = [ ./caisson ];
}
