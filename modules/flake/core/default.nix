# SPDX-License-Identifier: MIT
#
# The flake class's core module, forced into every
# evaluation of the flake-parts integration: the options of caisson
# (the `generic` registry entry `caisson`, reached through the closure)
# plus the mechanics of the class, the copies of `caisson.exports`
# into the flake outputs, the `systems` default and the checks under
# `perSystem`. A flake has no single system, so the `generic` entry
# `top-level-checks` is not imported.
{ closure-lib, ... }:
{ ... }:
{
  imports = [
    closure-lib.caisson.modules.generic.caisson
    ./caisson
    ./perSystem.nix
  ];
}
