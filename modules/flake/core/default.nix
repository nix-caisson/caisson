# SPDX-License-Identifier: MIT
#
# The flake class's core module, forced into every
# evaluation of the flake-parts integration: caisson's core
# module (the `generic` registry entry, reached through the closure)
# plus the mechanics of the class, the copies of `caisson.exports`
# into the flake outputs and the `systems` default.
{ closure-lib, ... }:
{ ... }:
{
  imports = [
    closure-lib.caisson-core.modules.generic.core
    ./caisson
  ];
}
