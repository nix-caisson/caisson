# SPDX-License-Identifier: MIT
#
# caisson's core module: the part of every framework module that is
# the same for every integrated class. It declares the composition's
# manifest, the configuration's name, the three registry selectors
# (`caisson.lib`, `caisson.libOverlays`, `caisson.modules.<class>`) and
# `caisson.exports`, what the selectors chose, which a top returns and
# a parent passes up. Plain modules on purpose: everything they need
# comes through `lib` (the composed library in specialArgs), so an
# integration imports this directory directly rather than through
# mkModule.
{ ... }:
{
  imports = [ ./caisson ];
}
