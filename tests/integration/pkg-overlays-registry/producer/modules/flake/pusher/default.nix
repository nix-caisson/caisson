# SPDX-License-Identifier: MIT
#
# A flake module that pushes an overlay into the `overlays.all` registry
# of whichever flake applies it. The consumer applies it, so the entry
# is registered there but defined in this project's files, and the
# consumer does not export it by default.
{ ... }:
{ ... }:
{
  caisson.nixpkgs.overlays.all.pushedIn = _namespace: _final: _prev: {
    pushedIn = true;
  };
}
