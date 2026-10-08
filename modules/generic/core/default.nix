# SPDX-License-Identifier: MIT
#
# caisson's core module: the part of every framework module that is
# the same for every class. It declares the composition's manifest, the
# registry selectors (`caisson.lib`, `caisson.libOverlays`,
# `caisson.modules.<class>`) and
# `caisson.exports`, what the selectors chose, which a top returns and
# a parent passes up. Registered under the class-free `generic` class
# (flake-parts' name for a module any class may import), and under
# every class whose integration forces it, as that class's `core`:
# `modules/structural/core` is a symlink here, and `modules/flake/core`
# imports this entry and adds the flake mechanics. Everything the
# modules beneath need comes through `lib`, the composed library in
# specialArgs.
#
# In an evaluation whose library is not a caisson composition the
# module declares nothing: a module list that carries it can be handed
# to an evaluator that runs on a library of its making, as
# home-manager's NixOS module does for the homes it embeds.
{ ... }:
{ lib, ... }:
{
  imports = if lib ? caisson && lib ? caisson-core then [ ./caisson ] else [ ];
}
